import Foundation

/// Rejects common OCR false positives on US driver's licenses before they reach the UI.
enum ScanFieldValidator {
    private static let nonNameTokens: Set<String> = [
        "limited", "term", "director", "motor", "vehicle", "department", "commissioner",
        "driver", "license", "licence", "identification", "identificationcard", "id",
        "class", "endorse", "restriction", "restrictions", "organ", "donor", "veteran",
        "commercial", "non", "compliant", "federal", "usa", "united", "states",
        "texas", "texass", "california", "florida", "new", "york", "dmv", "dds", "dps",
        "none", "eno",
        "locial", "seourta", "securi", "local", "secur", "social", "security", "administration",
        "given", "names", "name", "surname", "place", "birth", "piace", "nationality",
        "passport", "passeport", "pasaporte", "republic", "indian", "india", "issue",
        "expir", "expiration", "expiry", "nom", "nombres", "apellidos",
    ]

    private static let usStateCodes: Set<String> = [
        "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "FL", "GA", "HI", "ID", "IL", "IN", "IA",
        "KS", "KY", "LA", "ME", "MD", "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH", "NJ",
        "NM", "NY", "NC", "ND", "OH", "OK", "OR", "PA", "RI", "SC", "SD", "TN", "TX", "UT", "VT",
        "VA", "WA", "WV", "WI", "WY", "DC",
    ]

    static func isValid(_ suggestion: OcrFieldSuggestion, documentType: ScannedDocumentType) -> Bool {
        let value = suggestion.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return false }

        switch suggestion.profileKey {
        case ProfileFieldKey.displayName:
            return isPlausiblePersonName(value)
        case ProfileFieldKey.legalFirstName, ProfileFieldKey.legalMiddleName, ProfileFieldKey.legalLastName:
            return isPlausibleNameComponent(value)
        case ProfileFieldKey.ssn:
            return isPlausibleSSN(value)
        case ProfileFieldKey.driversLicenseNumber:
            return isPlausibleDriversLicenseNumber(value)
        case ProfileFieldKey.driversLicenseState:
            return isPlausibleUSState(value)
        case ProfileFieldKey.phoneMobile, ProfileFieldKey.phoneHome:
            return isPlausiblePhone(value, documentType: documentType)
        case ProfileFieldKey.postalCode:
            return value.range(of: #"^\d{5}(-\d{4})?$"#, options: .regularExpression) != nil
                || value.range(of: #"^\d{6}$"#, options: .regularExpression) != nil
        case ProfileFieldKey.addressLine1, ProfileFieldKey.passportAddress:
            if documentType == .passport {
                return !isOCRNoiseText(value) && value.count <= 90
            }
            return true
        default:
            return true
        }
    }

    static func filter(_ suggestions: [OcrFieldSuggestion], documentType: ScannedDocumentType) -> [OcrFieldSuggestion] {
        suggestions.filter { isValid($0, documentType: documentType) }
    }

    static func isOCRNoiseText(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return true }

        let noiseChars = "~`{}|\\[]<>?!@#$%^&*_=;:."
        let noiseCount = trimmed.filter { noiseChars.contains($0) }.count
        if noiseCount >= 2 { return true }
        if trimmed.count > 12, Double(noiseCount) / Double(trimmed.count) > 0.08 { return true }

        let letters = trimmed.filter(\.isLetter).count
        if trimmed.count > 20, Double(letters) / Double(trimmed.count) < 0.55 { return true }
        if trimmed.filter({ $0 == "~" || $0 == "_" || $0 == ";" }).count >= 2 { return true }
        return false
    }

    /// Single-token first/last names (Texas DL field 1 / field 2).
    static func isPlausibleNameComponent(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, trimmed.count <= 48 else { return false }
        if isOCRNoiseText(trimmed) { return false }
        if PassportBiodataSupport.isPassportFieldLabel(trimmed) { return false }
        let lower = trimmed.lowercased()
        if nonNameTokens.contains(lower) { return false }
        if DriverLicenseParserSupport.isStreetSuffixToken(trimmed) { return false }
        return trimmed.range(of: #"^[A-Za-z][A-Za-z\-']*$"#, options: .regularExpression) != nil
    }

    static func isPlausiblePersonName(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3, trimmed.count <= 64 else { return false }
        if isOCRNoiseText(trimmed) { return false }

        let lower = trimmed.lowercased()
        if nonNameTokens.contains(lower) { return false }
        for token in lower.split(whereSeparator: { !$0.isLetter }) {
            if nonNameTokens.contains(String(token)) { return false }
        }

        let bannedPhrases = [
            "limited term", "driver license", "drivers license", "identification card",
            "motor vehicle", "department of", "director of",
            "locial seourta", "social security", "localsecuri",
            "children:", "adults:", "do not sign", "your first job", "sign this card",
            "do not laminate", "until age",
        ]
        if bannedPhrases.contains(where: { lower.contains($0) }) { return false }

        // Must look like a personal name (letters, spaces, comma, hyphen).
        guard trimmed.range(of: #"^[A-Za-z][A-Za-z\-',\.\s]{2,}$"#, options: .regularExpression) != nil else {
            return false
        }

        let words = trimmed.split(separator: " ").map(String.init)
        guard words.count >= 2 || trimmed.contains(",") else { return false }
        if words.contains(where: { DriverLicenseParserSupport.isStreetSuffixToken($0) }) { return false }
        if DriverLicenseParserSupport.looksLikeStreetNameLine(trimmed) { return false }

        // Reject all-caps boilerplate under 3 words unless "LAST, FIRST" pattern.
        if trimmed == trimmed.uppercased(), !trimmed.contains(",") {
            let joined = words.joined(separator: " ").lowercased()
            if joined.contains("limited") || joined.contains("term") || joined.contains("director") {
                return false
            }
        }
        return true
    }

    static func isPlausibleSSN(_ value: String) -> Bool {
        let digits = value.filter(\.isNumber)
        guard digits.count == 9 else { return false }
        return value.range(of: #"^\d{3}-\d{2}-\d{4}$"#, options: .regularExpression) != nil
            || digits.count == 9
    }

    static func isPlausibleDriversLicenseNumber(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4, trimmed.count <= 20 else { return false }
        guard trimmed.rangeOfCharacter(from: .decimalDigits) != nil else { return false }
        // ZIP+4 is often OCR'd on its own line and must not become a DL number.
        if trimmed.range(of: #"^\d{5}-\d{4}$"#, options: .regularExpression) != nil {
            return false
        }

        let lower = trimmed.lowercased()
        let banned = ["director", "license", "driver", "limited", "term", "department", "motor", "vehicle"]
        if banned.contains(where: { lower == $0 || lower.contains($0) && !trimmed.contains(where: \.isNumber) }) {
            return false
        }
        return trimmed.range(of: #"^[A-Za-z0-9\-]+$"#, options: .regularExpression) != nil
    }

    static func isPlausibleUSState(_ value: String) -> Bool {
        let code = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard code.count == 2 else { return false }
        return usStateCodes.contains(code)
    }

    private static func isPlausiblePhone(_ value: String, documentType: ScannedDocumentType) -> Bool {
        let digits = value.filter(\.isNumber)
        guard digits.count == 10 || digits.count == 11 else { return false }
        // On DL scans, long digit runs are often document / audit numbers, not phones.
        if documentType == .driversLicense, digits.count == 11, digits.hasPrefix("1") {
            return false
        }
        return true
    }
}
