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
        if let idx = people.firstIndex(where: { $0.id == person.id }) {
            people[idx] = person
        } else {
            people.insert(person, at: 0)
        }
        if select {
            selectedPersonID = person.id
        }
        persist(person)
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
}

private enum CoreAPISync {
    private struct SaveRequest: Encodable {
        var id: String
        var display_name: String
        var fields: [String: String]
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
        set("first_name", person.firstName)
        set("last_name", person.lastName)
        // Demo form uses MM/DD/YYYY (date_of_birth).
        set("date_of_birth_mmddyyyy", person.dateOfBirthMMDDYYYY)
        if let mmdd = person.dateOfBirthMMDDYYYY {
            set("date_of_birth", mmdd)
        }
        set("address_line_1", person.addressLine1)
        set("city", person.city)
        set("state", person.state)
        set("postal_code", person.postalCode)
        set("insurance_provider", person.insuranceProvider)
        set("policy_number", person.policyNumber)

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

