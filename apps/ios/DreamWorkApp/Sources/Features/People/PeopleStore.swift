import Foundation

@MainActor
final class PeopleStore: ObservableObject {
    @Published private(set) var people: [PersonProfile] = []
    @Published var selectedPersonID: UUID?

    private let legacyStorageKey = "people.profiles.v1"
    private let selectedPersonKey = "people.selected_person_id.v1"
    private let db: PeopleSQLiteStore

    init() {
        let dbURL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("DreamWorkApp", isDirectory: true)
            .appendingPathComponent("people.sqlite3")

        try? FileManager.default.createDirectory(at: dbURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        db = try! PeopleSQLiteStore(dbPath: dbURL.path)

        migrateFromLegacyUserDefaultsIfNeeded()
        load()
    }

    var selectedPerson: PersonProfile? {
        guard let selectedPersonID else { return nil }
        return people.first(where: { $0.id == selectedPersonID })
    }

    func upsert(_ person: PersonProfile, select: Bool = true) {
        // Prevent duplicate rows for the same logical person (common when scans create new UUIDs).
        let incoming = canonicalizeAgainstExistingDuplicates(person)

        if let idx = people.firstIndex(where: { $0.id == incoming.id }) {
            people[idx] = incoming
        } else {
            people.insert(incoming, at: 0)
        }
        if select {
            selectedPersonID = incoming.id
        }
        persist(incoming)
    }

    func delete(_ id: UUID) {
        people.removeAll(where: { $0.id == id })
        if selectedPersonID == id {
            selectedPersonID = people.first?.id
        }
        try? db.deletePerson(id: id)
        persistSelectedPerson()
    }

    func deleteAll() {
        people = []
        selectedPersonID = nil
        try? db.deleteAllPeople()
        persistSelectedPerson()
    }

    func load() {
        people = (try? db.fetchAllPeople()) ?? []
        dedupeLoadedPeopleIfNeeded()
        if selectedPersonID == nil, let raw = UserDefaults.standard.string(forKey: selectedPersonKey) {
            selectedPersonID = UUID(uuidString: raw)
        }
        if selectedPersonID == nil {
            selectedPersonID = people.first?.id
        }
    }

    private func persist(_ person: PersonProfile) {
        try? db.upsertPerson(person)
        persistSelectedPerson()
        // Refresh ordering from DB (updated_at sort)
        load()

        // Best-effort sync to local core-api so the Chrome extension can use the same data.
        Task {
            await CoreAPISync.push(person: person)
        }
    }

    private func persistSelectedPerson() {
        if let selectedPersonID {
            UserDefaults.standard.set(selectedPersonID.uuidString, forKey: selectedPersonKey)
        } else {
            UserDefaults.standard.removeObject(forKey: selectedPersonKey)
        }
    }

    private func migrateFromLegacyUserDefaultsIfNeeded() {
        // If DB already has rows, don't import.
        if let existing = try? db.fetchAllPeople(), !existing.isEmpty {
            return
        }
        guard let data = UserDefaults.standard.data(forKey: legacyStorageKey),
              let decoded = try? JSONDecoder().decode([PersonProfile].self, from: data),
              !decoded.isEmpty else {
            return
        }
        for p in decoded {
            try? db.upsertPerson(p)
        }
        UserDefaults.standard.removeObject(forKey: legacyStorageKey)
    }

    private func dedupeLoadedPeopleIfNeeded() {
        // Group by nickname (case/whitespace-insensitive). If duplicates exist, merge into one row.
        var groups: [String: [PersonProfile]] = [:]
        for p in people {
            let key = Self.dedupeKey(for: p)
            groups[key, default: []].append(p)
        }

        var didChange = false
        for (_, group) in groups where group.count > 1 {
            // Prefer the oldest UUID as canonical stable id (min uuid string is arbitrary but stable).
            let canonical = group.sorted { $0.id.uuidString < $1.id.uuidString }.first!
            var merged = canonical
            for p in group where p.id != canonical.id {
                merged = Self.mergePeoplePreferNewerData(merged, p)
                try? db.deletePerson(id: p.id)
                didChange = true
            }
            merged.id = canonical.id
            merged.updatedAt = Date()
            try? db.upsertPerson(merged)
            didChange = true
        }

        if didChange {
            people = (try? db.fetchAllPeople()) ?? []
            // If selection pointed at a deleted duplicate, snap to the first remaining profile.
            if let selectedPersonID, !people.contains(where: { $0.id == selectedPersonID }) {
                self.selectedPersonID = people.first?.id
                persistSelectedPerson()
            }
        }
    }

    private func canonicalizeAgainstExistingDuplicates(_ incoming: PersonProfile) -> PersonProfile {
        let key = Self.dedupeKey(for: incoming)
        let matches = people.filter { Self.dedupeKey(for: $0) == key }
        guard !matches.isEmpty else { return incoming }

        // Keep a stable canonical UUID (oldest) so repeated scans don't create parallel identities.
        let canonical = matches.min(by: { $0.id.uuidString < $1.id.uuidString })!

        // If same UUID, nothing to do.
        if canonical.id == incoming.id { return incoming }

        // Merge into the existing canonical row and delete the incoming duplicate id.
        var merged = Self.mergePeoplePreferNewerData(canonical, incoming)
        merged.id = canonical.id
        merged.updatedAt = Date()

        // Delete duplicate row if it already exists in DB.
        if incoming.id != canonical.id {
            try? db.deletePerson(id: incoming.id)
        }

        // Remove duplicate from in-memory list (load() will refresh anyway).
        people.removeAll { $0.id == incoming.id && $0.id != canonical.id }

        return merged
    }

    private static func dedupeKey(for p: PersonProfile) -> String {
        let nick = p.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        if !nick.isEmpty {
            return nick.lowercased().replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        }
        // Fallback: derive a key from name-ish fields if nickname is empty.
        let fn = (p.firstName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let ln = (p.lastName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let full = [fn, ln].filter { !$0.isEmpty }.joined(separator: " ")
        if !full.isEmpty {
            return full.lowercased().replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        }
        return p.id.uuidString
    }

    private static func mergePeoplePreferNewerData(_ a: PersonProfile, _ b: PersonProfile) -> PersonProfile {
        // Prefer field values from the more recently updated profile when both sides have data.
        let newer = a.updatedAt >= b.updatedAt ? a : b
        let older = a.updatedAt >= b.updatedAt ? b : a
        var out = newer

        func preferMerged(_ newerVal: String?, _ olderVal: String?) -> String? {
            let n = (newerVal ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let o = (olderVal ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !n.isEmpty { return newerVal }
            if !o.isEmpty { return olderVal }
            return nil
        }

        out.nickname = preferMerged(newer.nickname, older.nickname) ?? out.nickname
        out.firstName = preferMerged(newer.firstName, older.firstName)
        out.lastName = preferMerged(newer.lastName, older.lastName)
        out.dateOfBirthMMDDYYYY = preferMerged(newer.dateOfBirthMMDDYYYY, older.dateOfBirthMMDDYYYY)
        out.height = preferMerged(newer.height, older.height)
        out.eyeColor = preferMerged(newer.eyeColor, older.eyeColor)

        out.email = preferMerged(newer.email, older.email)
        out.mobilePhone = preferMerged(newer.mobilePhone, older.mobilePhone)
        out.ssnLast4 = preferMerged(newer.ssnLast4, older.ssnLast4)
        out.insuranceProvider = preferMerged(newer.insuranceProvider, older.insuranceProvider)
        out.policyNumber = preferMerged(newer.policyNumber, older.policyNumber)

        out.addressLine1 = preferMerged(newer.addressLine1, older.addressLine1)
        out.addressLine2 = preferMerged(newer.addressLine2, older.addressLine2)
        out.city = preferMerged(newer.city, older.city)
        out.state = preferMerged(newer.state, older.state)
        out.postalCode = preferMerged(newer.postalCode, older.postalCode)

        out.driverLicenseNumber = preferMerged(newer.driverLicenseNumber, older.driverLicenseNumber)
        out.driverLicenseIssueMMDDYYYY = preferMerged(newer.driverLicenseIssueMMDDYYYY, older.driverLicenseIssueMMDDYYYY)
        out.driverLicenseExpiryMMDDYYYY = preferMerged(newer.driverLicenseExpiryMMDDYYYY, older.driverLicenseExpiryMMDDYYYY)
        out.driverLicenseState = preferMerged(newer.driverLicenseState, older.driverLicenseState)

        // Merge collections (dedupe by id).
        out.driverLicenses = mergeById(older.driverLicenses, newer.driverLicenses)
        out.documents = mergeById(older.documents, newer.documents)
        out.familyMembers = mergeById(older.familyMembers, newer.familyMembers)
        out.emergencyContacts = mergeById(older.emergencyContacts, newer.emergencyContacts)

        // Merge genAI fields (prefer non-empty newer-ish values).
        var g = older.genAIFields
        for (k, v) in newer.genAIFields {
            let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { continue }
            if (g[k] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                g[k] = v
            } else if newer.updatedAt >= older.updatedAt {
                g[k] = v
            }
        }
        out.genAIFields = g

        return out
    }

    private static func mergeById<T: Identifiable>(_ a: [T], _ b: [T]) -> [T] where T.ID: Hashable {
        var seen = Set<T.ID>()
        var out: [T] = []
        for x in a + b {
            if seen.contains(x.id) { continue }
            seen.insert(x.id)
            out.append(x)
        }
        return out
    }
}

enum CoreAPISync {
    private struct SaveRequest: Encodable {
        var id: String
        var display_name: String
        var fields: [String: String]
    }

    private struct ReadResponse: Decodable {
        var id: String
        var display_name: String?
        var fields: [String: String]
    }

    private struct ProfileKeyRow: Decodable {
        var entry_id: String
        var profile_key: String
    }

    static func push(person: PersonProfile) async {
        guard let url = URL(string: "http://127.0.0.1:18081/manual-entry") else { return }

        let profileName = person.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        if profileName.isEmpty { return }

        let id = profileIdFromName(profileName)
        var fields: [String: String] = [:]

        func set(_ key: String, _ value: String?) {
            let t = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty {
                fields[key] = t
            }
        }

        set("display_name", person.displayTitle)
        // Stable key used by the Chrome extension profile picker + iOS pull sync.
        // This prevents mismatches when nickname != extension profile name.
        set("profile_key", profileName)
        set("first_name", person.firstName)
        set("last_name", person.lastName)
        // Demo form uses MM/DD/YYYY (date_of_birth).
        set("date_of_birth_mmddyyyy", person.dateOfBirthMMDDYYYY)
        if let mmdd = person.dateOfBirthMMDDYYYY {
            set("date_of_birth", mmdd)
        }
        // Persist common DL attributes derived from OCR/GenAI.
        // Keep these as first-class keys so the browser extension can reliably fill them.
        set("height", person.height)
        set("eye_color", person.eyeColor)
        set("address_line_1", person.addressLine1)
        set("city", person.city)
        set("state", person.state)
        set("postal_code", person.postalCode)
        set("insurance_provider", person.insuranceProvider)
        set("policy_number", person.policyNumber)
        // Demo form + extension use guardian_* keys for parent contact fields.
        set("guardian_email", person.email)
        set("guardian_phone", person.mobilePhone)

        // Push any extra GenAI-extracted fields too (best-effort).
        for (k, v) in person.genAIFields {
            set(k, v)
        }

        let body = SaveRequest(
            id: id,
            display_name: person.displayTitle,
            fields: fields
        )
        guard let data = try? JSONEncoder().encode(body) else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = data
        req.timeoutInterval = 1.5

        _ = try? await URLSession.shared.data(for: req)
    }

    static func pull(profileHints: [String]) async -> [String: String]? {
        let hints = profileHints
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if hints.isEmpty { return nil }

        func norm(_ s: String) -> String {
            s.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .lowercased()
        }

        var hintSet = Set(hints.map(norm))

        // Build candidate ids from hints (unique, stable order).
        var candidateIDs: [String] = []
        for h in hints {
            candidateIDs.append(profileIdFromName(h))
        }

        // Expand hints using the profile_key index (helps when nickname != browser profile name).
        if let rows = await fetchProfileKeyIndex() {
            for row in rows {
                let pk = row.profile_key.trimmingCharacters(in: .whitespacesAndNewlines)
                if pk.isEmpty { continue }
                let pkN = norm(pk)

                // Direct hint match.
                if hintSet.contains(pkN) {
                    candidateIDs.append(row.entry_id)
                    continue
                }

                // Token overlap match (e.g. hint contains first name and profile_key is full name).
                let pkTokens = Set(pkN.split(separator: " ").map(String.init))
                if !pkTokens.isEmpty {
                    for h in hintSet {
                        let htokens = Set(h.split(separator: " ").map(String.init))
                        let inter = pkTokens.intersection(htokens)
                        if inter.count >= 2 || (inter.count == 1 && pkTokens.count == 1) {
                            hintSet.insert(pkN)
                            candidateIDs.append(row.entry_id)
                            break
                        }
                    }
                }
            }
        }

        var seenIDs = Set<String>()
        candidateIDs = candidateIDs.filter { seenIDs.insert($0).inserted }

        struct Scored: Hashable {
            var score: Int
            var fields: [String: String]
        }

        var best: Scored?
        var merged: [String: String] = [:]

        for id in candidateIDs {
            guard let url = URL(string: "http://127.0.0.1:18081/manual-entry/\(id)") else { continue }

            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.timeoutInterval = 1.5

            do {
                let (data, response) = try await URLSession.shared.data(for: req)
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                guard (200..<300).contains(status) else { continue }
                let decoded = try JSONDecoder().decode(ReadResponse.self, from: data)

                var score = 0
                if let pk = decoded.fields["profile_key"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !pk.isEmpty {
                    if hintSet.contains(norm(pk)) { score += 100 }
                    else {
                        // Explicit mismatch: don't use this record.
                        score = -10_000
                    }
                }

                // If the record id matches one of the hinted slugs, that's a strong signal too.
                if score > -1_000 {
                    if hintSet.contains(norm(id.replacingOccurrences(of: "profile-", with: "").replacingOccurrences(of: "-", with: " "))) {
                        score += 50
                    }
                }

                let candidate = Scored(score: score, fields: decoded.fields)
                if let b = best {
                    if candidate.score > b.score { best = candidate }
                } else {
                    best = candidate
                }

                // Merge non-conflicting fields across all plausible candidates (helps fill insurance/etc.)
                if score >= 0 {
                    for (k, v) in decoded.fields {
                        let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
                        if t.isEmpty { continue }
                        if (merged[k] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            merged[k] = v
                        }
                    }
                }
            } catch {
                continue
            }
        }

        guard let best, best.score >= 0 else { return nil }
        // Prefer the best-scoring record, but fill gaps from other high-confidence merges.
        var out = best.fields
        for (k, v) in merged {
            let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { continue }
            if (out[k] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                out[k] = v
            }
        }
        return out
    }

    private static func fetchProfileKeyIndex() async -> [ProfileKeyRow]? {
        guard let url = URL(string: "http://127.0.0.1:18081/manual-entry/profile-keys") else { return nil }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 1.5

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            guard (200..<300).contains(status) else { return nil }
            return try JSONDecoder().decode([ProfileKeyRow].self, from: data)
        } catch {
            return nil
        }
    }

    private static func profileIdFromName(_ name: String) -> String {
        let n = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
        if n.isEmpty { return "profile-unknown" }
        let slug = n.replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
        return "profile-\(slug)"
    }

}

