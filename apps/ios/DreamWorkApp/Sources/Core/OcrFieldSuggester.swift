import Foundation

struct OcrFieldSuggestion: Identifiable, Hashable {
    let profileKey: String
    let label: String
    let value: String
    let confidence: String

    var id: String { profileKey }
}

enum OcrFieldSuggester {
    static func suggest(from fullText: String, documentType: ScannedDocumentType) -> [OcrFieldSuggestion] {
        let text = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }

        let raw: [OcrFieldSuggestion]
        switch documentType {
        case .driversLicense:
            raw = suggestDriversLicense(from: text)
        default:
            raw = suggestGeneric(from: text, documentType: documentType)
        }
        return ScanFieldValidator.filter(raw, documentType: documentType)
    }

    /// Uses the dedicated DL parser (labels, LAST/FIRST, address, dates) — not naive line guessing.
    private static func suggestDriversLicense(from text: String) -> [OcrFieldSuggestion] {
        let parsed = DriverLicenseParser.parse(text)
        return DriverLicenseFieldMapper.suggestions(from: parsed)
    }

    private static func suggestGeneric(from text: String, documentType: ScannedDocumentType) -> [OcrFieldSuggestion] {
        var out: [OcrFieldSuggestion] = []
        func add(_ key: String, _ label: String, _ value: String, _ confidence: String) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            out.append(OcrFieldSuggestion(profileKey: key, label: label, value: trimmed, confidence: confidence))
        }

        if let email = firstMatch(in: text, pattern: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, options: [.caseInsensitive]) {
            add(ProfileFieldKey.email, "Email", email, "High")
        }

        if let phone = firstMatch(in: text, pattern: #"\(?\d{3}\)?[-.\s]\d{3}[-.\s]\d{4}"#) {
            add(ProfileFieldKey.phoneMobile, "Mobile phone", phone, "Medium")
        }

        for pattern in [
            #"\b(\d{1,2}[/-]\d{1,2}[/-]\d{2,4})\b"#,
            #"\b(\d{4}-\d{2}-\d{2})\b"#,
        ] {
            if let dob = firstMatch(in: text, pattern: pattern) {
                add(ProfileFieldKey.dateOfBirth, "Date of birth", dob, "Medium")
                break
            }
        }

        if let zip = firstMatch(in: text, pattern: #"\b(\d{5}(?:-\d{4})?)\b"#) {
            add(ProfileFieldKey.postalCode, "ZIP / postal code", zip, "Medium")
        }

        switch documentType {
        case .passport:
            if let passport = firstMatch(in: text, pattern: #"\b([A-Z]{1,2}\d{6,9})\b"#) {
                add(ProfileFieldKey.passportNumber, "Passport number", passport, "Medium")
            }
        case .insuranceCard:
            if let member = firstMatch(
                in: text,
                pattern: #"(?:MEMBER|ID|SUBSCRIBER)[#:\s]*([A-Z0-9]{6,20})"#,
                options: [.caseInsensitive]
            ), member.rangeOfCharacter(from: .decimalDigits) != nil {
                add(ProfileFieldKey.insuranceMemberId, "Insurance member ID", member, "Medium")
            }
        default:
            break
        }

        var seen = Set<String>()
        return out.filter { seen.insert($0.profileKey).inserted }
    }

    static func fullText(from document: VisionOcrAdapter.NormalizedDocument) -> String {
        document.pages
            .flatMap(\.blocks)
            .map(\.text)
            .joined(separator: "\n")
    }

    private static func firstMatch(
        in text: String,
        pattern: String,
        options: NSRegularExpression.Options = []
    ) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        if match.numberOfRanges > 1, let r = Range(match.range(at: 1), in: text) {
            return String(text[r])
        }
        if let r = Range(match.range, in: text) {
            return String(text[r])
        }
        return nil
    }
}
