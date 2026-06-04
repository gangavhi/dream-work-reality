import Foundation

/// Normalizes extracted field values and removes duplicate profile keys.
enum FieldNormalizationEngine {
    static func normalize(_ suggestions: [OcrFieldSuggestion]) -> [OcrFieldSuggestion] {
        deduplicate(suggestions.map(normalizeField))
    }

    static func normalizeField(_ suggestion: OcrFieldSuggestion) -> OcrFieldSuggestion {
        let value = normalizeValue(suggestion.value, profileKey: suggestion.profileKey)
        guard value != suggestion.value else { return suggestion }
        return OcrFieldSuggestion(
            profileKey: suggestion.profileKey,
            label: suggestion.label,
            value: value,
            confidence: suggestion.confidence,
            confidenceScore: suggestion.confidenceScore,
            mappingSource: suggestion.mappingSource,
            confidenceBreakdown: suggestion.confidenceBreakdown
        )
    }

    private static func normalizeValue(_ raw: String, profileKey: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        switch profileKey {
        case ProfileFieldKey.legalFirstName, ProfileFieldKey.legalMiddleName, ProfileFieldKey.legalLastName,
             ProfileFieldKey.displayName, ProfileFieldKey.emergencyContactName:
            return normalizeName(trimmed)
        case ProfileFieldKey.dateOfBirth, ProfileFieldKey.driversLicenseIssueDate,
             ProfileFieldKey.driversLicenseExpiry, ProfileFieldKey.passportExpiry, ProfileFieldKey.stateIdExpiry:
            return normalizeDate(trimmed)
        case ProfileFieldKey.addressLine1, ProfileFieldKey.addressLine2, ProfileFieldKey.city:
            return normalizeAddressComponent(trimmed)
        case ProfileFieldKey.state, ProfileFieldKey.driversLicenseState:
            return normalizeState(trimmed)
        case ProfileFieldKey.postalCode:
            return normalizePostal(trimmed)
        case ProfileFieldKey.ssn:
            return normalizeSSN(trimmed)
        case ProfileFieldKey.driversLicenseNumber, ProfileFieldKey.passportNumber, ProfileFieldKey.stateIdNumber,
             ProfileFieldKey.insuranceMemberId:
            return normalizeDocumentNumber(trimmed)
        case ProfileFieldKey.phoneMobile, ProfileFieldKey.phoneHome, ProfileFieldKey.emergencyContactPhone:
            return normalizePhone(trimmed)
        case ProfileFieldKey.email:
            return trimmed.lowercased()
        default:
            return collapseWhitespace(trimmed)
        }
    }

    static func normalizeName(_ raw: String) -> String {
        let collapsed = collapseWhitespace(raw)
        return collapsed
            .split(separator: " ")
            .map { part -> String in
                let s = String(part)
                let letters = s.filter(\.isLetter)
                if !letters.isEmpty, letters == letters.uppercased(), letters.count > 1 {
                    return s
                }
                if s.count <= 2, s == s.uppercased() { return s }
                return s.prefix(1).uppercased() + s.dropFirst().lowercased()
            }
            .joined(separator: " ")
    }

    static func normalizeDate(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split { $0 == "/" || $0 == "-" || $0 == "." }.map(String.init)
        if parts.count == 3,
           let a = Int(parts[0]), let b = Int(parts[1]), var y = Int(parts[2])
        {
            if y < 100 { y += y >= 50 ? 1900 : 2000 }
            if (1900 ..< 2100).contains(y) {
                if (1 ... 12).contains(a), (1 ... 31).contains(b) {
                    return String(format: "%04d-%02d-%02d", y, a, b)
                }
                if (1 ... 12).contains(b), (1 ... 31).contains(a) {
                    return String(format: "%04d-%02d-%02d", y, b, a)
                }
            }
        }
        let digits = trimmed.filter(\.isNumber)
        if digits.count == 8 {
            let y = Int(digits.prefix(4)) ?? 0
            let m = Int(digits.dropFirst(4).prefix(2)) ?? 0
            let d = Int(digits.suffix(2)) ?? 0
            if (1900 ..< 2100).contains(y), (1 ... 12).contains(m), (1 ... 31).contains(d) {
                return String(format: "%04d-%02d-%02d", y, m, d)
            }
        }
        return trimmed
    }

    private static func normalizeAddressComponent(_ raw: String) -> String {
        collapseWhitespace(raw)
            .split(separator: " ")
            .map { token -> String in
                let s = String(token)
                if s.count <= 2, s == s.uppercased() { return s }
                if s.range(of: #"^\d+[A-Za-z]?$"#, options: .regularExpression) != nil { return s.uppercased() }
                return s.prefix(1).uppercased() + s.dropFirst().lowercased()
            }
            .joined(separator: " ")
    }

    private static func normalizeState(_ raw: String) -> String {
        let upper = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if upper.count == 2 { return upper }
        return upper
    }

    private static func normalizePostal(_ raw: String) -> String {
        let digits = raw.filter(\.isNumber)
        guard digits.count >= 5 else { return raw.trimmingCharacters(in: .whitespacesAndNewlines) }
        let base = String(digits.prefix(5))
        if digits.count >= 9 {
            return "\(base)-\(digits.dropFirst(5).prefix(4))"
        }
        return base
    }

    private static func normalizeSSN(_ raw: String) -> String {
        let digits = raw.filter(\.isNumber)
        guard digits.count == 9 else { return raw.trimmingCharacters(in: .whitespacesAndNewlines) }
        let d = Array(digits)
        return "\(d[0..<3].map(String.init).joined())-\(d[3..<5].map(String.init).joined())-\(d[5..<9].map(String.init).joined())"
    }

    private static func normalizeDocumentNumber(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
    }

    private static func normalizePhone(_ raw: String) -> String {
        let digits = raw.filter(\.isNumber)
        guard digits.count >= 10 else { return collapseWhitespace(raw) }
        let last10 = String(digits.suffix(10))
        let area = last10.prefix(3)
        let mid = last10.dropFirst(3).prefix(3)
        let end = last10.suffix(4)
        return "(\(area)) \(mid)-\(end)"
    }

    private static func collapseWhitespace(_ raw: String) -> String {
        raw.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func deduplicate(_ suggestions: [OcrFieldSuggestion]) -> [OcrFieldSuggestion] {
        var bestByKey: [String: OcrFieldSuggestion] = [:]
        for suggestion in suggestions {
            let key = suggestion.profileKey
            guard let existing = bestByKey[key] else {
                bestByKey[key] = suggestion
                continue
            }
            if suggestion.confidenceScore > existing.confidenceScore {
                bestByKey[key] = suggestion
            }
        }
        return ProfileSchema.sortSuggestions(Array(bestByKey.values))
    }
}
