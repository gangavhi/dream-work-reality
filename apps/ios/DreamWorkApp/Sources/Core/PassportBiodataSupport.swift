import Foundation

/// Shared biodata sanitization for US and Indian passport OCR parsers.
enum PassportBiodataSupport {
    private static let labelPhrases: Set<String> = [
        "given names", "given name", "given name(s)", "given name (s)",
        "surname", "sur name", "nom", "apellidos", "prénoms", "nombres",
        "place of birth", "piace of birth", "lieu de naissance", "lugar de nacimiento",
        "place of issue", "date of birth", "date de naissance", "fecha de nacimiento",
        "date of issue", "date de délivrance", "fecha de expedición",
        "date of expiration", "date d'expiration", "fecha de caducidad",
        "nationality", "nationalité", "nacionalidad",
        "passport no", "passport number", "no du passeport", "no de pasaporte",
        "passport", "sex", "type", "code", "authority",
    ]

    private static let nationalityValues: Set<String> = [
        "united states of america", "republic of india", "indian", "india", "usa",
    ]

    private static let labelTokens: Set<String> = [
        "given", "names", "name", "surname", "place", "birth", "piace", "issue",
        "expir", "expiration", "expiry", "nationality", "national", "passport",
        "passeport", "pasaporte", "nom", "nombres", "prénoms", "apellidos",
        "republic", "indian", "india", "united", "states", "america", "date",
        "of", "du", "de", "la", "el", "lieu", "lugar", "fecha",
    ]

    static func isPassportFieldLabel(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }

        let normalized = trimmed
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[^\w\s/()]"#, with: "", options: .regularExpression)

        if labelPhrases.contains(normalized) { return true }

        let words = normalized.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return true }

        if words.allSatisfy({ labelTokens.contains($0) || $0.count <= 2 }) {
            return true
        }

        if normalized.hasPrefix("place of"), normalized.contains("birth") { return true }
        if normalized.hasPrefix("given"), normalized.contains("name") { return true }
        if normalized.hasPrefix("date of") { return true }

        return false
    }

    static func sanitizeBiodataValue(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        if nationalityValues.contains(normalized) { return trimmed }
        guard !isPassportFieldLabel(trimmed) else { return nil }
        return trimmed
    }

    static func sanitizeNameValue(_ value: String) -> String? {
        guard let trimmed = sanitizeBiodataValue(value) else { return nil }
        let words = trimmed
            .replacingOccurrences(of: ".", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .map { String($0) }
            .filter { !labelTokens.contains($0.lowercased()) }
            .filter { ScanFieldValidator.isPlausibleNameComponent($0) }
        guard !words.isEmpty else { return nil }
        return words.joined(separator: " ")
    }

    static func isPlausiblePlaceValue(_ value: String) -> Bool {
        guard let trimmed = sanitizeBiodataValue(value) else { return false }
        let upper = trimmed.uppercased()
        if upper.count < 3 { return false }
        if upper.contains(",") { return true }
        if upper.range(of: #"\b[A-Z]{2,}\b"#, options: .regularExpression) != nil { return true }
        return false
    }

    static func valueOnNextLine(
        matching labelNeedles: [String],
        in lines: [String],
        accept: (String) -> Bool
    ) -> String? {
        for (idx, line) in lines.enumerated() {
            let lower = line.lowercased()
            guard labelNeedles.contains(where: { lower.contains($0) }) else { continue }

            if let inline = inlineValue(on: line, labelNeedles: labelNeedles), accept(inline) {
                return inline
            }

            for offset in 1 ... 2 where idx + offset < lines.count {
                let candidate = lines[idx + offset].trimmingCharacters(in: .whitespacesAndNewlines)
                if accept(candidate) { return candidate }
            }
        }
        return nil
    }

    static func isPlausibleDateOfBirth(
        _ dob: String,
        issueDate: String? = nil,
        expiryDate: String? = nil
    ) -> Bool {
        guard let dobParts = parseSlashedDate(dob) else { return false }

        let currentYear = Calendar.current.component(.year, from: Date())
        if dobParts.year > currentYear { return false }

        if let issueDate, let issueParts = parseSlashedDate(issueDate) {
            if compare(dobParts, issueParts) != .orderedAscending { return false }
        }

        if let expiryDate, let expiryParts = parseSlashedDate(expiryDate) {
            if dobParts.year >= expiryParts.year { return false }
        }

        return true
    }

    // MARK: - Private

    private struct DateParts: Comparable {
        let year: Int
        let month: Int
        let day: Int

        static func < (lhs: DateParts, rhs: DateParts) -> Bool {
            if lhs.year != rhs.year { return lhs.year < rhs.year }
            if lhs.month != rhs.month { return lhs.month < rhs.month }
            return lhs.day < rhs.day
        }
    }

    private static func compare(_ lhs: DateParts, _ rhs: DateParts) -> ComparisonResult {
        if lhs < rhs { return .orderedAscending }
        if lhs == rhs { return .orderedSame }
        return .orderedDescending
    }

    private static func parseSlashedDate(_ raw: String) -> DateParts? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let regex = try? NSRegularExpression(pattern: #"^(\d{2})/(\d{2})/(\d{4})$"#),
              let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
              match.numberOfRanges > 3,
              let aR = Range(match.range(at: 1), in: trimmed),
              let bR = Range(match.range(at: 2), in: trimmed),
              let yR = Range(match.range(at: 3), in: trimmed)
        else { return nil }

        let a = Int(trimmed[aR]) ?? 0
        let b = Int(trimmed[bR]) ?? 0
        let year = Int(trimmed[yR]) ?? 0
        guard (1 ... 12).contains(a) || (1 ... 12).contains(b),
              (1 ... 31).contains(a) || (1 ... 31).contains(b),
              (1900 ... 2100).contains(year)
        else { return nil }

        // US passports use MM/DD/YYYY in this app; Indian uses DD/MM/YYYY — both are valid if in range.
        let month = (1 ... 12).contains(a) ? a : b
        let day = (1 ... 31).contains(b) && a != month ? b : a
        return DateParts(year: year, month: month, day: day)
    }

    private static func inlineValue(on line: String, labelNeedles: [String]) -> String? {
        let lower = line.lowercased()
        guard labelNeedles.contains(where: { lower.contains($0) }) else { return nil }

        if let colon = line.firstIndex(of: ":") {
            let tail = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return tail.isEmpty ? nil : tail
        }

        for needle in labelNeedles.sorted(by: { $0.count > $1.count }) {
            guard let range = lower.range(of: needle) else { continue }
            let tail = String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if tail.hasPrefix("/") || tail.hasPrefix("-") {
                let trimmed = tail.drop(while: { $0 == "/" || $0 == "-" || $0.isWhitespace }).trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            if !tail.isEmpty, !isPassportFieldLabel(tail) {
                return tail
            }
        }
        return nil
    }
}
