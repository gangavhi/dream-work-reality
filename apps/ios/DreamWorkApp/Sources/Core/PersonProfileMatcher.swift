import Foundation

/// Links a scanned document to an existing profile using DOB, name, address, and ID fields.
enum PersonProfileMatcher {
    struct MatchResult {
        let personID: String
        let reasons: [String]
    }

    /// Picks the best existing profile for incoming scan fields.
    static func matchExistingPerson(
        among people: [PersonRecord],
        fieldUpdates: [String: String],
        resolution: PersonResolutionSuggestion?
    ) -> MatchResult? {
        if let resolution,
           resolution.resolution == .matchExisting,
           let personID = resolution.personID,
           people.contains(where: { $0.id == personID })
        {
            let reasons = resolution.candidates.first(where: { $0.personID == personID })?.reasons ?? []
            return MatchResult(personID: personID, reasons: reasons)
        }

        let scannedDOB = fieldUpdates[ProfileFieldKey.dateOfBirth]
        let scannedLast = fieldUpdates[ProfileFieldKey.legalLastName]
        let scannedFirst = fieldUpdates[ProfileFieldKey.legalFirstName]
        let scannedAddress = fieldUpdates[ProfileFieldKey.addressLine1]
        let scannedPostal = fieldUpdates[ProfileFieldKey.postalCode]
        let scannedDL = fieldUpdates[ProfileFieldKey.driversLicenseNumber]
        let scannedPassport = fieldUpdates[ProfileFieldKey.passportNumber]

        var best: MatchResult?
        var bestScore = 0

        for person in people {
            var reasons: [String] = []
            var score = 0

            if let scannedDL, !scannedDL.isEmpty,
               normalizeID(scannedDL) == normalizeID(person.value(for: ProfileFieldKey.driversLicenseNumber))
            {
                score += 100
                reasons.append("drivers_license_number")
            }

            if let scannedPassport, !scannedPassport.isEmpty,
               normalizeID(scannedPassport) == normalizeID(person.value(for: ProfileFieldKey.passportNumber))
            {
                score += 100
                reasons.append("passport_number")
            }

            let personDOB = person.value(for: ProfileFieldKey.dateOfBirth)
            if let scannedDOB, !scannedDOB.isEmpty, !personDOB.isEmpty,
               dobMatches(scannedDOB, personDOB)
            {
                score += 40
                reasons.append("date_of_birth")
            }

            let personLast = person.value(for: ProfileFieldKey.legalLastName)
            if let scannedLast, !scannedLast.isEmpty, !personLast.isEmpty,
               normalizeName(scannedLast) == normalizeName(personLast)
            {
                score += 22
                reasons.append("legal_last_name")
            }

            let personFirst = person.value(for: ProfileFieldKey.legalFirstName)
            if let scannedFirst, !scannedFirst.isEmpty, !personFirst.isEmpty,
               namesSimilar(scannedFirst, personFirst)
            {
                score += 20
                reasons.append("legal_first_name")
            }

            let personAddress = person.value(for: ProfileFieldKey.addressLine1)
            if let scannedAddress, !scannedAddress.isEmpty, !personAddress.isEmpty,
               namesSimilar(scannedAddress, personAddress)
            {
                score += 10
                reasons.append("address_line1")
            }

            let personPostal = person.value(for: ProfileFieldKey.postalCode)
            if let scannedPostal, !scannedPostal.isEmpty, !personPostal.isEmpty,
               normalizePostal(scannedPostal) == normalizePostal(personPostal)
            {
                score += 8
                reasons.append("postal_code")
            }

            let personDisplay = person.value(for: ProfileFieldKey.displayName)
            if let scannedDisplay = fieldUpdates[ProfileFieldKey.displayName], !scannedDisplay.isEmpty,
               !personDisplay.isEmpty,
               namesSimilar(scannedDisplay, personDisplay)
            {
                score += 7
                reasons.append("display_name")
            }

            let hasDOB = reasons.contains("date_of_birth")
            let secondaryCount = reasons.filter { $0 != "date_of_birth" }.count
            if hasDOB, secondaryCount >= 1 {
                score += 30
                reasons.append("dob_with_secondary_fields")
            }

            if score > bestScore {
                bestScore = score
                best = MatchResult(personID: person.id, reasons: reasons)
            }
        }

        guard let best, bestScore >= 72 else { return nil }
        return best
    }

    static func dobMatches(_ left: String, _ right: String) -> Bool {
        let formsLeft = dobForms(from: left)
        let formsRight = dobForms(from: right)
        guard !formsLeft.isEmpty, !formsRight.isEmpty else { return false }
        return formsLeft.contains(where: { formsRight.contains($0) })
    }

    static func dobForms(from raw: String) -> Set<String> {
        var forms = Set<String>()
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split { $0 == "/" || $0 == "-" || $0 == "." }.map(String.init)
        if parts.count == 3,
           let a = Int(parts[0]), let b = Int(parts[1]), let y = Int(parts[2]),
           (1900 ..< 2100).contains(y)
        {
            if (1 ... 12).contains(a), (1 ... 31).contains(b) {
                forms.insert(String(format: "%04d%02d%02d", y, a, b))
            }
            if (1 ... 12).contains(b), (1 ... 31).contains(a) {
                forms.insert(String(format: "%04d%02d%02d", y, b, a))
            }
        }

        forms.formUnion(dobCanonicalForms(trimmed))
        return forms
    }

    static func dobCanonicalForms(_ raw: String) -> Set<String> {
        let digits = raw.filter(\.isNumber)
        guard digits.count >= 8 else { return [] }

        let d = String(digits.prefix(8))
        var forms: Set<String> = [d]

        let yyyy = Int(d.prefix(4)) ?? 0
        let mm = Int(d.dropFirst(4).prefix(2)) ?? 0
        let dd = Int(d.dropFirst(6).prefix(2)) ?? 0
        if (1900 ..< 2100).contains(yyyy), (1 ... 12).contains(mm), (1 ... 31).contains(dd) {
            forms.insert(String(format: "%02d%02d%04d", mm, dd, yyyy))
        }

        let mmLead = Int(d.prefix(2)) ?? 0
        let ddMid = Int(d.dropFirst(2).prefix(2)) ?? 0
        let yyyyTail = Int(d.suffix(4)) ?? 0
        if (1 ... 12).contains(mmLead), (1 ... 31).contains(ddMid), (1900 ..< 2100).contains(yyyyTail) {
            forms.insert(String(format: "%04d%02d%02d", yyyyTail, mmLead, ddMid))
        }

        return forms
    }

    private static func normalizeName(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private static func namesSimilar(_ left: String, _ right: String) -> Bool {
        let a = normalizeName(left)
        let b = normalizeName(right)
        guard !a.isEmpty, !b.isEmpty else { return false }
        if a == b { return true }
        if a.contains(b) || b.contains(a) { return true }
        return levenshteinRatio(a, b) >= 0.72
    }

    private static func normalizeID(_ raw: String) -> String {
        raw.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func normalizePostal(_ raw: String) -> String {
        String(raw.filter(\.isNumber).prefix(5))
    }

    private static func levenshteinRatio(_ a: String, _ b: String) -> Double {
        let dist = levenshtein(Array(a), Array(b))
        let maxLen = max(a.count, b.count)
        guard maxLen > 0 else { return 1.0 }
        return 1.0 - (Double(dist) / Double(maxLen))
    }

    private static func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }

        var prev = Array(0 ... b.count)
        var curr = Array(repeating: 0, count: b.count + 1)

        for (i, ca) in a.enumerated() {
            curr[0] = i + 1
            for (j, cb) in b.enumerated() {
                let cost = ca == cb ? 0 : 1
                curr[j + 1] = min(prev[j + 1] + 1, curr[j] + 1, prev[j] + cost)
            }
            swap(&prev, &curr)
        }
        return prev[b.count]
    }
}
