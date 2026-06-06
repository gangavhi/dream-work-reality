import Foundation

/// Extracts identity fields from any OCR text (SSN card, DL, passport, tax forms, etc.).
enum UniversalDocumentParser {
    static func parse(from text: String) -> [OcrFieldSuggestion] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        if looksLikeSSNDocument(trimmed) {
            return parseSSAStub(from: trimmed)
        }

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
                    confidenceScore: score
                )
            )
        }

        if let ssn = extractSSN(from: trimmed) {
            add(ProfileFieldKey.ssn, "Social Security Number", ssn, "High", 0.92)
        }

        let names = shouldIncludeDriverLicenseFields(in: trimmed) ? ParsedNames() : extractNames(from: trimmed)
        if let display = names.display {
            add(ProfileFieldKey.displayName, "Full name", display, "High", 0.9)
        }
        if let first = names.first {
            add(ProfileFieldKey.legalFirstName, "Legal first name", first, "High", 0.88)
        }
        if let last = names.last {
            add(ProfileFieldKey.legalLastName, "Legal last name", last, "High", 0.88)
        }

        if let dob = extractDOB(from: trimmed) {
            add(ProfileFieldKey.dateOfBirth, "Date of birth", dob, "High", 0.88)
        }

        let upper = trimmed.uppercased()
        if upper.contains("W-2") || upper.contains("FORM W2") || upper.range(of: #"\bW2\b"#, options: .regularExpression) != nil {
            add(ProfileFieldKey.taxFormType, "Tax form type", "W-2", "High", 0.88)
        } else if upper.contains("1099") {
            add(ProfileFieldKey.taxFormType, "Tax form type", "1099", "High", 0.88)
        }

        if shouldIncludeDriverLicenseFields(in: trimmed) {
            let dl = DriverLicenseParser.parse(trimmed)
            suggestions.append(contentsOf: DriverLicenseFieldMapper.suggestions(from: dl))
        }

        if let addr = extractAddress(from: trimmed) {
            add(ProfileFieldKey.addressLine1, "Address line 1", addr.street, "Medium", 0.75)
            add(ProfileFieldKey.city, "City", addr.city, "Medium", 0.72)
            add(ProfileFieldKey.state, "State / province", addr.state, "Medium", 0.72)
            add(ProfileFieldKey.postalCode, "ZIP / postal code", addr.zip, "Medium", 0.72)
        }

        return dedupeByKey(suggestions)
    }

    /// SSA card / stub detection (tolerates common Vision OCR garbles of the header).
    static func looksLikeSSNDocument(_ text: String) -> Bool {
        let upper = text.uppercased()
        if upper.contains("DRIVER") && upper.contains("LICENSE") { return false }
        guard text.range(of: #"\b\d{3}-\d{2}-\d{4}\b"#, options: .regularExpression) != nil else {
            return false
        }
        return hasSSAHeaderSignals(upper)
    }

    // MARK: - SSA stub layout

    private static func parseSSAStub(from text: String) -> [OcrFieldSuggestion] {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var suggestions: [OcrFieldSuggestion] = []
        let context = DocumentFieldLabelContext.from(fieldValues: [:], documentType: .ssnCard)

        func add(_ key: String, _ label: String, _ value: String, _ score: Double) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let resolvedLabel = ProfileSchema.definition(for: key)?.label
                ?? DocumentFieldLabels.label(for: key, context: context)
            suggestions.append(
                OcrFieldSuggestion(
                    profileKey: key,
                    label: label.isEmpty ? resolvedLabel : label,
                    value: trimmed,
                    confidence: score >= 0.85 ? "High" : "Medium",
                    confidenceScore: score
                )
            )
        }

        if let ssn = extractSSN(from: text) {
            add(ProfileFieldKey.ssn, "Social Security Number", ssn, 0.95)
        }

        if let name = extractSSACardholderName(from: lines) {
            add(ProfileFieldKey.displayName, "Full name", name.display, 0.92)
            add(ProfileFieldKey.legalFirstName, "Legal first name", name.first, 0.9)
            add(ProfileFieldKey.legalLastName, "Legal last name", name.last, 0.9)
        }

        if let dob = extractLabeledDOB(from: text) {
            add(ProfileFieldKey.dateOfBirth, "Date of birth", dob, 0.88)
        }

        if let addr = extractSSAMailingAddress(from: lines) {
            if !addr.street.isEmpty {
                add(ProfileFieldKey.addressLine1, "Address line 1", addr.street, 0.82)
            }
            add(ProfileFieldKey.city, "City", addr.city, 0.8)
            add(ProfileFieldKey.state, "State / province", addr.state, 0.8)
            add(ProfileFieldKey.postalCode, "ZIP / postal code", addr.zip, 0.8)
        }

        return dedupeByKey(suggestions)
    }

    private static func hasSSAHeaderSignals(_ upper: String) -> Bool {
        if upper.contains("SOCIAL SECURITY") || upper.contains("YOUR SOCIAL SECURITY CARD") {
            return true
        }
        if upper.contains("ESTABLISHED FOR") || upper.contains("LOCALSECURI") {
            return true
        }
        if upper.range(of: #"(?i)LOCIAL\s+SEC"#, options: .regularExpression) != nil {
            return true
        }
        if upper.range(of: #"(?i)SOCIAL\s+SECUR"#, options: .regularExpression) != nil {
            return true
        }
        if upper.contains("LOCIAL") && upper.contains("SEC") {
            return true
        }
        return false
    }

    private struct SSAParsedName {
        let display: String
        let first: String
        let last: String
    }

    private static func extractSSACardholderName(from lines: [String]) -> SSAParsedName? {
        if let streetIdx = lines.firstIndex(where: isSSAStreetLine) {
            for idx in stride(from: streetIdx - 1, through: max(0, streetIdx - 4), by: -1) {
                if let name = parseSSANameLine(lines[idx]) {
                    return name
                }
            }
        }

        if let cardIdx = lines.firstIndex(where: { $0.uppercased().contains("YOUR SOCIAL SECURITY CARD") }) {
            for idx in (cardIdx + 1) ..< lines.count {
                if isSSAStreetLine(lines[idx]) || isSSACityStateZipLine(lines[idx]) { break }
                if let name = parseSSANameLine(lines[idx]) {
                    return name
                }
            }
        }

        for line in lines.reversed() {
            if isSSAStreetLine(line) || isSSACityStateZipLine(line) { continue }
            if let name = parseSSANameLine(line) {
                return name
            }
        }

        for idx in 0 ..< lines.count - 1 {
            let firstLine = stripNameLine(lines[idx])
            let secondLine = stripNameLine(lines[idx + 1])
            guard isSingleNameToken(firstLine), isSingleNameToken(secondLine) else { continue }
            guard !isSSAOCRGarbageToken(firstLine), !isSSAOCRGarbageToken(secondLine) else { continue }
            guard !isSSABoilerplateLine(firstLine), !isSSABoilerplateLine(secondLine) else { continue }
            let first = DriverLicenseFormatting.personName(firstLine)
            let last = DriverLicenseFormatting.personName(secondLine)
            guard let display = DriverLicenseFormatting.displayName(first: first, middle: nil, last: last),
                  !display.isEmpty
            else { continue }
            return SSAParsedName(display: display, first: first, last: last)
        }
        return nil
    }

    private static func parseSSANameLine(_ line: String) -> SSAParsedName? {
        let cleaned = line
            .replacingOccurrences(of: #"^\d+\.?\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, !isSSABoilerplateLine(cleaned) else { return nil }

        let words = cleaned.split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count >= 2, words.count <= 4 else { return nil }
        guard words.allSatisfy({ ScanFieldValidator.isPlausibleNameComponent($0) }) else { return nil }
        guard !words.contains(where: { isSSAOCRGarbageToken($0) }) else { return nil }

        let first = DriverLicenseFormatting.personName(words[0])
        let last = DriverLicenseFormatting.personName(words[words.count - 1])
        let middle = words.count > 2
            ? words.dropFirst().dropLast().joined(separator: " ")
            : nil
        guard let display = DriverLicenseFormatting.displayName(first: first, middle: middle, last: last),
              !display.isEmpty
        else { return nil }
        return SSAParsedName(display: display, first: first, last: last)
    }

    private static func isSSAOCRGarbageToken(_ token: String) -> Bool {
        let upper = token.uppercased()
        let garbage = [
            "LOCIAL", "SEOURTA", "SECURI", "LOCAL", "SECUR", "SEO", "SOCIAL", "SECURITY",
            "ADMINISTRATION", "CARD", "SIGN", "ADULTS", "CHILDREN", "PLEASE", "KEEP",
            "NUMBER", "ESTABLISHED", "YOUR", "THIS", "OTHER", "SIDE", "STUB",
        ]
        return garbage.contains(upper) || upper.hasSuffix("SECURI") || upper.hasPrefix("LOC")
    }

    private static func isSSABoilerplateLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        let banned = [
            "social security", "administration", "established for", "this number",
            "your social", "sign this card", "do not carry", "do not laminate",
            "keep your card", "keep this stub", "please note", "adults:", "children:",
            "locial", "seourta", "securi", "localsecuri",
        ]
        return banned.contains(where: { lower.contains($0) })
    }

    private static func extractLabeledDOB(from text: String) -> String? {
        let patterns = [
            #"(?i)(?:DOB|DATE\s+OF\s+BIRTH|BIRTH\s+DATE|BIRTHDATE)\s*[#:\s]*(\d{1,2}[/-]\d{1,2}[/-]\d{2,4})"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: text)
            else { continue }
            return String(text[range])
        }
        return nil
    }

    private static func extractSSAMailingAddress(from lines: [String]) -> ParsedAddress? {
        guard let streetIdx = lines.firstIndex(where: isSSAStreetLine) else { return nil }
        let street = DriverLicenseFormatting.streetAddress(lines[streetIdx])

        for idx in streetIdx ..< min(streetIdx + 3, lines.count) {
            if let csz = DriverLicenseParserSupport.parseCityStateZip(lines[idx]) {
                return ParsedAddress(
                    street: street,
                    city: DriverLicenseFormatting.city(csz.city),
                    state: csz.state,
                    zip: DriverLicenseFormatting.zip5(csz.zip)
                )
            }
        }
        return nil
    }

    private static func isSSAStreetLine(_ line: String) -> Bool {
        line.range(of: #"^\d+\s+[A-Za-z0-9].*(?:\b(?:RD|ROAD|ST|STREET|AVE|AVENUE|DR|DRIVE|LN|LANE|BLVD|WAY|CT|COURT)\b)"#,
                   options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func isSSACityStateZipLine(_ line: String) -> Bool {
        DriverLicenseParserSupport.parseCityStateZip(line) != nil
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
            (#"(?i)^(?:PARTY\s+[AB]|SPOUSE)\s*[#:\s]+(.+)$"#, 1),
            (#"(?i)^(?:EMPLOYEE|SUBSCRIBER)\s*[#:\s]+(.+)$"#, 1),
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

        for line in lines {
            if isPlausibleNameLine(line), !isBoilerplateLine(line) {
                applyName(line, to: &result)
                break
            }
        }

        return result
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

    private static func shouldIncludeDriverLicenseFields(in text: String) -> Bool {
        if looksLikeSSNDocument(text) {
            return false
        }
        let upper = text.uppercased()
        return upper.contains("DRIVER")
            || upper.contains("LICENSE")
            || upper.contains("IDENTIFICATION")
            || upper.range(of: #"(?i)4\s*D\.?\s*DL"#, options: .regularExpression) != nil
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
            "locial", "seourta", "securi", "localsecuri",
        ]
        return banned.contains(where: { lower.contains($0) })
    }

    // MARK: - DOB / address

    private static func extractDOB(from text: String) -> String? {
        if looksLikeSSNDocument(text) {
            return extractLabeledDOB(from: text)
        }
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
