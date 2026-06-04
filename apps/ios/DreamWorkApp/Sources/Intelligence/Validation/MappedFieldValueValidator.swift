import Foundation

/// Rejects label→value assignments where the value shape does not match the profile field type.
enum MappedFieldValueValidator {
    static func accepts(profileKey: String, value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        switch profileKey {
        case ProfileFieldKey.legalFirstName, ProfileFieldKey.legalLastName,
             ProfileFieldKey.legalMiddleName, ProfileFieldKey.displayName:
            return looksLikePersonName(trimmed) && !looksLikeStreetAddress(trimmed)

        case ProfileFieldKey.addressLine1, ProfileFieldKey.addressLine2:
            return looksLikeStreetAddress(trimmed) || looksLikeCityStateLine(trimmed)

        case ProfileFieldKey.city:
            return looksLikeCityName(trimmed)

        case ProfileFieldKey.state:
            return trimmed.count <= 3 || trimmed.range(of: #"^[A-Za-z\s]{2,24}$"#, options: .regularExpression) != nil

        case ProfileFieldKey.postalCode:
            return trimmed.range(of: #"\d{4,}"#, options: .regularExpression) != nil

        case ProfileFieldKey.dateOfBirth, ProfileFieldKey.driversLicenseExpiry,
             ProfileFieldKey.driversLicenseIssueDate, ProfileFieldKey.passportExpiry:
            return looksLikeDate(trimmed)

        case ProfileFieldKey.driversLicenseNumber, ProfileFieldKey.passportNumber:
            return trimmed.range(of: #"[A-Z0-9]{5,}"#, options: .regularExpression) != nil

        case ProfileFieldKey.gender:
            let upper = trimmed.uppercased()
            return ["M", "F", "X", "MALE", "FEMALE", "OTHER"].contains(upper)

        default:
            return true
        }
    }

    static func looksLikePersonName(_ text: String) -> Bool {
        guard text.range(of: #"^[A-Za-z][A-Za-z\s\-'.]{0,48}$"#, options: .regularExpression) != nil else {
            return false
        }
        return text.range(of: #"\d"#, options: .regularExpression) == nil
    }

    static func looksLikeStreetAddress(_ text: String) -> Bool {
        let upper = text.uppercased()
        if text.range(of: #"^\d+\s+\S"#, options: .regularExpression) != nil { return true }
        let streetTokens = [" ST", " STREET", " AVE", " AVENUE", " RD", " ROAD", " DR", " DRIVE", " LN", " LANE", " BLVD", " WAY", " CT", " COURT"]
        return streetTokens.contains(where: { upper.contains($0) })
    }

    static func looksLikeCityStateLine(_ text: String) -> Bool {
        text.range(of: #"\d{5}(-\d{4})?"#, options: .regularExpression) != nil
    }

    static func looksLikeCityName(_ text: String) -> Bool {
        looksLikePersonName(text) && !looksLikeStreetAddress(text)
    }

    static func looksLikeDate(_ text: String) -> Bool {
        text.range(of: #"\d{1,2}[/.-]\d{1,2}[/.-]\d{2,4}"#, options: .regularExpression) != nil
            || text.range(of: #"\d{4}[/.-]\d{1,2}[/.-]\d{1,2}"#, options: .regularExpression) != nil
    }

    /// OCR value tokens (surnames, given names, cities) must not become spatial pairing labels.
    static func looksLikeStandaloneValue(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 48 else { return false }
        if trimmed.contains(":") { return false }
        if matchesKnownLabelPhrase(trimmed) { return false }
        if looksLikeDate(trimmed) { return true }
        if looksLikeStreetAddress(trimmed) { return true }
        if looksLikeCityStateLine(trimmed) { return true }

        let words = trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        if words.count == 1,
           trimmed == trimmed.uppercased(),
           trimmed.rangeOfCharacter(from: .letters) != nil,
           trimmed.rangeOfCharacter(from: .decimalDigits) == nil,
           trimmed.count >= 2, trimmed.count <= 24
        {
            return true
        }
        if words.count >= 2, trimmed == trimmed.uppercased(), looksLikeStreetAddress(trimmed) {
            return true
        }
        return false
    }

    private static func matchesKnownLabelPhrase(_ text: String) -> Bool {
        let normalized = text.lowercased()
            .replacingOccurrences(of: #"^\d+\.\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: ":", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let phrases = [
            "surname", "given name", "given names", "first name", "last name", "name",
            "dob", "date of birth", "address", "nationality", "sex", "gender",
            "passport", "license", "expiry", "expiration", "issue",
        ]
        return phrases.contains(where: { normalized == $0 || normalized.hasPrefix($0 + " ") || normalized.hasSuffix(" " + $0) })
    }
}
