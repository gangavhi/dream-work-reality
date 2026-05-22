import Foundation

/// Extracts identity fields from any OCR text (SSN card, DL, passport, tax forms, etc.).
enum UniversalDocumentParser {
    static func parse(from text: String) -> [OcrFieldSuggestion] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var suggestions: [OcrFieldSuggestion] = []
        let context = DocumentFieldLabelContext.from(fieldValues: [:], documentType: .other)

        func add(_ key: String, _ label: String, _ value: String?, _ confidence: String, _ score: Double) {
            let v = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !v.isEmpty else { return }
            let resolvedLabel = ProfileSchema.definition(for: key)?.label
                ?? DocumentFieldLabels.label(for: key, context: context)
            suggestions.append(
                OcrFieldSuggestion(
                    profileKey: key,
                    label: label.isEmpty ? resolvedLabel : label,
                    value: v,
                    confidence: confidence,
                    confidenceScore: score,
                    mappingSource: .estimated
                )
            )
        }

        if let ssn = extractSSN(from: trimmed) {
            add(ProfileFieldKey.ssn, "Social Security Number", ssn, "Estimated", 0.58)
        }

        let names = extractNames(from: trimmed)
        if let display = names.display {
            add(ProfileFieldKey.displayName, "Full name", display, "Estimated", 0.55)
        }
        if let first = names.first {
            add(ProfileFieldKey.legalFirstName, "Legal first name", first, "Estimated", 0.52)
        }
        if let last = names.last {
            add(ProfileFieldKey.legalLastName, "Legal last name", last, "Estimated", 0.52)
        }

        if let dob = extractDOB(from: trimmed) {
            add(ProfileFieldKey.dateOfBirth, "Date of birth", dob, "Estimated", 0.5)
        }

        if let addr = extractAddress(from: trimmed) {
            add(ProfileFieldKey.addressLine1, "Address line 1", addr.street, "Estimated", 0.48)
            add(ProfileFieldKey.city, "City", addr.city, "Estimated", 0.45)
            add(ProfileFieldKey.state, "State / province", addr.state, "Estimated", 0.45)
            add(ProfileFieldKey.postalCode, "ZIP / postal code", addr.zip, "Estimated", 0.45)
        }

        return dedupeByKey(suggestions)
    }

    // MARK: - SSN

    private static func extractSSN(from text: String) -> String? {
        let patterns = [
            #"(?i)(?:SSN|SOCIAL\s+SECURITY(?:\s+NUMBER)?)\s*[#:\s]*(\d{3}[-\s]?\d{2}[-\s]?\d{4})"#,
            #"\b(\d{3}-\d{2}-\d{4})\b"#,
            #"(?i)SSN\s*(\d{9})\b"#,
        ]
        for pattern in patterns {
            if let raw = firstMatch(in: text, pattern: pattern) {
                return formatSSN(raw)
            }
        }
        return nil
    }

    private static func formatSSN(_ raw: String) -> String {
        let digits = raw.filter(\.isNumber)
        guard digits.count == 9 else { return raw.trimmingCharacters(in: .whitespacesAndNewlines) }
        let i = digits.startIndex
        let a = digits.index(i, offsetBy: 3)
        let b = digits.index(a, offsetBy: 2)
        return "\(digits[i..<a])-\(digits[a..<b])-\(digits[b...])"
    }

    // MARK: - Names

    private struct ParsedNames {
        var display: String?
        var first: String?
        var last: String?
    }

    private static func extractNames(from text: String) -> ParsedNames {
        var result = ParsedNames()
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let labeledPatterns: [(String, Int)] = [
            (#"(?i)^(?:NAME|FULL\s+NAME|HOLDER|CARDHOLDER)\s*[#:\s]+(.+)$"#, 1),
            (#"(?i)^(?:THIS\s+NUMBER\s+HAS\s+BEEN\s+ESTABLISHED\s+FOR)\s*(.+)$"#, 1),
        ]

        for line in lines {
            for (pattern, group) in labeledPatterns {
                if let name = captureGroup(in: line, pattern: pattern, group: group),
                   isPlausibleNameLine(name)
                {
                    applyName(name, to: &result)
                    return result
                }
            }
        }

        let upper = text.uppercased()
        if upper.contains("SOCIAL SECURITY") {
            if let paired = extractConsecutiveNameLines(from: lines, order: .firstLast) {
                return paired
            }
            for line in lines {
                if isPlausibleNameLine(line), !isBoilerplateLine(line) {
                    applyName(line, to: &result)
                    return result
                }
            }
        }

        for line in lines {
            if isPlausibleNameLine(line), !isBoilerplateLine(line) {
                applyName(line, to: &result)
                break
            }
        }

        return result
    }

    private enum NameLineOrder {
        case firstLast
        case lastFirst
    }

    private static func extractConsecutiveNameLines(from lines: [String], order: NameLineOrder) -> ParsedNames? {
        for idx in 0 ..< lines.count - 1 {
            let firstLine = stripNameLine(lines[idx])
            let secondLine = stripNameLine(lines[idx + 1])
            guard isSingleNameToken(firstLine), isSingleNameToken(secondLine) else { continue }

            var result = ParsedNames()
            switch order {
            case .firstLast:
                result.first = DriverLicenseFormatting.personName(firstLine)
                result.last = DriverLicenseFormatting.personName(secondLine)
            case .lastFirst:
                result.last = DriverLicenseFormatting.personName(firstLine)
                result.first = DriverLicenseFormatting.personName(secondLine)
            }
            result.display = DriverLicenseFormatting.displayName(
                first: result.first,
                middle: nil,
                last: result.last
            )
            return result
        }
        return nil
    }

    private static func stripNameLine(_ line: String) -> String {
        line
            .replacingOccurrences(of: #"^\d+\.?\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^[^\p{L}]+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isSingleNameToken(_ token: String) -> Bool {
        guard !token.isEmpty else { return false }
        return ScanFieldValidator.isPlausibleNameComponent(token)
    }

    private static func applyName(_ raw: String, to result: inout ParsedNames) {
        let cleaned = raw
            .replacingOccurrences(of: #"^\d+\.?\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^[^\p{L}]+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.contains(",") {
            let parts = cleaned.split(separator: ",", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 {
                result.last = DriverLicenseFormatting.personName(parts[0])
                result.first = DriverLicenseFormatting.personName(parts[1])
                result.display = DriverLicenseFormatting.displayName(first: result.first, middle: nil, last: result.last)
                return
            }
        }

        let words = cleaned.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard words.count >= 2 else {
            result.display = DriverLicenseFormatting.personName(cleaned)
            return
        }

        // SSN cards often print FIRST LAST; Texas DL uses LAST then FIRST on separate lines.
        result.first = DriverLicenseFormatting.personName(words[0])
        result.last = DriverLicenseFormatting.personName(words[words.count - 1])
        if words.count > 2 {
            let middle = words.dropFirst().dropLast().joined(separator: " ")
            result.display = DriverLicenseFormatting.displayName(
                first: result.first,
                middle: DriverLicenseFormatting.personName(middle),
                last: result.last
            )
        } else {
            result.display = DriverLicenseFormatting.displayName(
                first: result.first,
                middle: nil,
                last: result.last
            )
        }
    }

    private static func isPlausibleNameLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3, trimmed.count <= 64 else { return false }
        guard trimmed.range(of: #"^[A-Za-z][A-Za-z\-',\.\s]{2,}$"#, options: .regularExpression) != nil else {
            return false
        }
        let words = trimmed.split(separator: " ")
        guard words.count >= 2 else { return false }
        return !isBoilerplateLine(trimmed)
    }

    private static func isBoilerplateLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        let banned = [
            "social security", "administration", "department", "driver", "license",
            "identification", "united states", "signature", "valid", "for official",
            "this number", "established for", "signature of", "date of",
        ]
        return banned.contains(where: { lower.contains($0) })
    }

    // MARK: - DOB / address

    private static func extractDOB(from text: String) -> String? {
        let patterns = [
            #"(?i)(?:DOB|DATE\s+OF\s+BIRTH|BIRTH\s+DATE|BIRTHDATE)\s*[#:\s]*(\d{1,2}[/-]\d{1,2}[/-]\d{2,4})"#,
            #"\b(\d{2}/\d{2}/\d{4})\b"#,
        ]
        for pattern in patterns {
            if let dob = firstMatch(in: text, pattern: pattern) {
                return dob
            }
        }
        return nil
    }

    private struct ParsedAddress {
        let street: String
        let city: String
        let state: String
        let zip: String
    }

    private static func extractAddress(from text: String) -> ParsedAddress? {
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            if let csz = DriverLicenseParserSupport.parseCityStateZip(line) {
                return ParsedAddress(
                    street: "",
                    city: DriverLicenseFormatting.city(csz.city),
                    state: csz.state,
                    zip: DriverLicenseFormatting.zip5(csz.zip)
                )
            }
        }
        for line in lines {
            if line.range(of: #"^\d+\s+\S+"#, options: .regularExpression) != nil {
                if let cszIdx = lines.firstIndex(where: { DriverLicenseParserSupport.parseCityStateZip($0) != nil }),
                   cszIdx > lines.firstIndex(of: line) ?? -1,
                   let csz = DriverLicenseParserSupport.parseCityStateZip(lines[cszIdx])
                {
                    return ParsedAddress(
                        street: DriverLicenseFormatting.streetAddress(line),
                        city: DriverLicenseFormatting.city(csz.city),
                        state: csz.state,
                        zip: DriverLicenseFormatting.zip5(csz.zip)
                    )
                }
            }
        }
        return nil
    }

    // MARK: - Helpers

    private static func dedupeByKey(_ suggestions: [OcrFieldSuggestion]) -> [OcrFieldSuggestion] {
        var byKey: [String: OcrFieldSuggestion] = [:]
        for item in suggestions {
            if let existing = byKey[item.profileKey] {
                if item.confidenceScore > existing.confidenceScore {
                    byKey[item.profileKey] = item
                }
            } else {
                byKey[item.profileKey] = item
            }
        }
        return ProfileSchema.sortSuggestions(Array(byKey.values))
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        captureGroup(in: text, pattern: pattern, group: 1) ?? captureGroup(in: text, pattern: pattern, group: 0)
    }

    private static func captureGroup(in text: String, pattern: String, group: Int) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        if group == 0, let r = Range(match.range, in: text) {
            return String(text[r])
        }
        guard match.numberOfRanges > group, let r = Range(match.range(at: group), in: text) else { return nil }
        return String(text[r])
    }
}
