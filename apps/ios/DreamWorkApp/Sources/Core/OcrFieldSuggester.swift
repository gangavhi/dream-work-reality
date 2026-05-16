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

        var out: [OcrFieldSuggestion] = []
        func add(_ key: String, _ label: String, _ value: String, _ confidence: String) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            out.append(OcrFieldSuggestion(profileKey: key, label: label, value: trimmed, confidence: confidence))
        }

        if let email = firstMatch(in: text, pattern: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, options: [.caseInsensitive]) {
            add(ProfileFieldKey.email, "Email", email, "High")
        }

        if let phone = firstMatch(in: text, pattern: #"(?:\+?1[-.\s]?)?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}"#) {
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

        if let zip = firstMatch(in: text, pattern: #"\b\d{5}(?:-\d{4})?\b"#) {
            add(ProfileFieldKey.postalCode, "ZIP / postal code", zip, "Medium")
        }

        if let state = firstMatch(in: text, pattern: #"\b([A-Z]{2})\b"#) {
            add(ProfileFieldKey.driversLicenseState, "State", state, "Low")
        }

        switch documentType {
        case .driversLicense:
            if let dl = firstMatch(
                in: text,
                pattern: #"(?:DL|LIC|LICENSE)[#:\s]*([A-Z0-9]{5,15})"#,
                options: [.caseInsensitive]
            ) {
                add(ProfileFieldKey.driversLicenseNumber, "Driver license number", dl, "Medium")
            } else if let dl = firstMatch(in: text, pattern: #"\b[A-Z]\d{7,12}\b"#) {
                add(ProfileFieldKey.driversLicenseNumber, "Driver license number", dl, "Low")
            }
        case .passport:
            if let passport = firstMatch(in: text, pattern: #"\b[A-Z]{1,2}\d{6,9}\b"#) {
                add(ProfileFieldKey.passportNumber, "Passport number", passport, "Medium")
            }
            if let mrz = text.split(separator: "\n").first(where: { $0.contains("P<") || $0.count >= 40 }) {
                add(ProfileFieldKey.passportNumber, "Passport MRZ line", String(mrz.prefix(44)), "Low")
            }
        case .insuranceCard:
            if let member = firstMatch(
                in: text,
                pattern: #"(?:MEMBER|ID|SUBSCRIBER)[#:\s]*([A-Z0-9]{6,20})"#,
                options: [.caseInsensitive]
            ) {
                add(ProfileFieldKey.insuranceMemberId, "Insurance member ID", member, "Medium")
            }
        case .other:
            break
        }

        let lines = text
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count >= 3 && $0.count <= 48 }

        if let nameLine = lines.first(where: { !$0.contains("@") && !$0.contains(where: \.isNumber) }) {
            add(ProfileFieldKey.displayName, "Display name", nameLine, "Low")
            let parts = nameLine.split(separator: " ").map(String.init)
            if parts.count >= 2 {
                add(ProfileFieldKey.legalFirstName, "Legal first name", parts[0], "Low")
                add(ProfileFieldKey.legalLastName, "Legal last name", parts[parts.count - 1], "Low")
            }
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
