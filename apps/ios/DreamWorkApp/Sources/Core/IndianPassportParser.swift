import Foundation

/// Parses Indian passport biodata / MRZ text (Republic of India, country code IND).
enum IndianPassportParser {
    struct ParsedPassport {
        var firstName: String?
        var middleName: String?
        var lastName: String?
        var passportNumber: String?
        var nationality: String?
        var dateOfBirth: String?
        var issueDate: String?
        var expiryDate: String?
        var placeOfBirth: String?
        var placeOfIssue: String?
        var countryCode: String = "IN"
    }

    static func parse(from text: String) -> ParsedPassport? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, isIndianPassport(trimmed) else { return nil }

        let lines = trimmed
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map { OcrTextPostProcessor.cleanLine($0) }
            .filter { !$0.isEmpty }

        var result = ParsedPassport()
        parseMRZ(from: lines, into: &result)
        parseLabeledFields(from: lines, joined: trimmed, into: &result)
        parseStandaloneNameLines(from: lines, into: &result)
        normalizeDates(in: &result)

        guard result.lastName != nil
            || result.firstName != nil
            || result.passportNumber != nil
            || result.dateOfBirth != nil
        else { return nil }

        return result
    }

    static func suggestions(from text: String) -> [OcrFieldSuggestion] {
        guard let parsed = parse(from: text) else { return [] }

        let context = DocumentFieldLabelContext(
            documentType: .passport,
            issuerRegion: nil,
            country: parsed.countryCode
        )

        var out: [OcrFieldSuggestion] = []
        func add(_ key: String, _ value: String?, _ score: Double) {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmed.isEmpty else { return }
            out.append(
                OcrFieldSuggestion(
                    profileKey: key,
                    label: DocumentFieldLabels.label(for: key, context: context),
                    value: trimmed,
                    confidence: score >= 0.9 ? "High" : "Medium",
                    confidenceScore: score
                )
            )
        }

        let first = parsed.firstName.map { DriverLicenseFormatting.personName($0) }
        let middle = parsed.middleName.map { DriverLicenseFormatting.personName($0) }
        let last = parsed.lastName.map { DriverLicenseFormatting.personName($0) }
        let display = DriverLicenseFormatting.displayName(first: first, middle: middle, last: last)

        add(ProfileFieldKey.displayName, display, 0.96)
        add(ProfileFieldKey.legalFirstName, first, 0.96)
        add(ProfileFieldKey.legalMiddleName, middle, 0.85)
        add(ProfileFieldKey.legalLastName, last, 0.96)
        add(ProfileFieldKey.passportNumber, parsed.passportNumber, 0.95)
        add(ProfileFieldKey.passportCountry, parsed.nationality ?? "IND", 0.92)
        add(ProfileFieldKey.passportExpiry, parsed.expiryDate, 0.93)
        add(ProfileFieldKey.dateOfBirth, parsed.dateOfBirth, 0.94)
        add(ProfileFieldKey.country, parsed.countryCode, 0.9)

        if let issue = parsed.issueDate {
            _ = issue // biodata issue date captured internally; no dedicated schema key yet
        }
        if let pob = parsed.placeOfBirth {
            add("place_of_birth", pob, 0.75)
        }
        if let poi = parsed.placeOfIssue {
            add("place_of_issue", poi, 0.72)
        }

        var seen = Set<String>()
        return ScanFieldValidator.filter(
            out.filter { seen.insert($0.profileKey).inserted },
            documentType: .passport
        )
    }

    // MARK: - Detection

    static func isIndianPassport(_ text: String) -> Bool {
        let upper = text.uppercased()
        if upper.contains("REPUBLIC OF INDIA") { return true }
        if upper.contains("GOVERNMENT OF INDIA") { return true }
        if upper.contains("P<IND") || upper.contains("<IND") { return true }
        if upper.contains("INDIAN") && upper.contains("PASSPORT") { return true }
        if upper.range(of: #"\bIND\b"#, options: .regularExpression) != nil,
           upper.contains("PASSPORT"),
           upper.range(of: #"\b[A-Z]\d{7}\b"#, options: .regularExpression) != nil
        {
            return true
        }
        return false
    }

    // MARK: - MRZ (TD3)

    private static func parseMRZ(from lines: [String], into result: inout ParsedPassport) {
        for (idx, line) in lines.enumerated() {
            let isNameLine = line.uppercased().contains("P<IND") || line.contains("<<")
            let compact = isNameLine ? fixMRZNameLine(line) : fixMRZNumericLine(line)

            if compact.contains("P<IND") || compact.hasPrefix("P<IND") {
                parseMRZLine1(compact, into: &result)
            }

            if let passport = extractPassportNumberFromMRZ(compact) {
                result.passportNumber = result.passportNumber ?? passport
            }

            if let dob = extractDOBFromMRZ(compact) {
                result.dateOfBirth = result.dateOfBirth ?? dob
            }

            if let expiry = extractExpiryFromMRZ(compact) {
                result.expiryDate = result.expiryDate ?? expiry
            }

            if idx > 0 {
                let prev = lines[idx - 1]
                let prevCompact = fixMRZNameLine(prev)
                if prevCompact.contains("P<IND") || prevCompact.contains("<<") {
                    parseMRZLine1(prevCompact, into: &result)
                }
            }
        }
    }

    /// MRZ line 1 (names) — do not map letters O→0.
    private static func fixMRZNameLine(_ line: String) -> String {
        line.replacingOccurrences(of: " ", with: "").uppercased()
    }

    /// MRZ line 2 (passport no / dates) — OCR digit fixes only.
    private static func fixMRZNumericLine(_ line: String) -> String {
        var compact = line
            .replacingOccurrences(of: " ", with: "")
            .uppercased()
        compact = compact.replacingOccurrences(of: "O", with: "0")
        compact = compact.replacingOccurrences(of: "Q", with: "0")
        compact = compact.replacingOccurrences(
            of: #"(?<=\d)K(?=\d)"#,
            with: "4",
            options: .regularExpression
        )
        return compact
    }

    /// @deprecated Use fixMRZNameLine / fixMRZNumericLine
    private static func fixMRZCompact(_ line: String) -> String {
        line.uppercased().contains("P<IND") ? fixMRZNameLine(line) : fixMRZNumericLine(line)
    }

    private static func parseMRZLine1(_ line: String, into result: inout ParsedPassport) {
        guard let range = line.range(of: "P<IND") else { return }
        let tail = String(line[range.upperBound...])
        let parts = tail.split(separator: "<", omittingEmptySubsequences: false).map(String.init)
        guard !parts.isEmpty else { return }

        let last = parts[0].replacingOccurrences(of: "<", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        let givenParts = parts.dropFirst().joined(separator: " ")
            .replacingOccurrences(of: "<", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty && ScanFieldValidator.isPlausibleNameComponent($0) }

        if result.lastName == nil, ScanFieldValidator.isPlausibleNameComponent(last) {
            result.lastName = DriverLicenseFormatting.personName(last)
        }
        if result.firstName == nil, let first = givenParts.first {
            result.firstName = DriverLicenseFormatting.personName(first)
        }
        if result.middleName == nil, givenParts.count > 1 {
            result.middleName = DriverLicenseFormatting.personName(givenParts.dropFirst().joined(separator: " "))
        }
    }

    private static func extractPassportNumberFromMRZ(_ compact: String) -> String? {
        let patterns = [
            #"(?i)([A-Z]\d{7})<\dIND"#,
            #"(?i)^([A-Z0-9<]{9})\dIND"#,
            #"(?i)\b([A-Z]\d{7})\b"#,
        ]
        for pattern in patterns {
            if let raw = firstCapture(in: compact, pattern: pattern),
               isPlausibleIndianPassportNumber(raw)
            {
                return normalizePassportNumber(raw)
            }
        }
        return nil
    }

    private static func extractDOBFromMRZ(_ compact: String) -> String? {
        let patterns = [
            #"(?i)IND(\d{6})"#,
            #"(?i)IND[^0-9]{0,6}(\d{6})"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: compact, range: NSRange(compact.startIndex..., in: compact)),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: compact)
            else { continue }
            if let parsed = mrzDateString(String(compact[range])) {
                return parsed
            }
        }
        return nil
    }

    private static func extractExpiryFromMRZ(_ compact: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"(?i)IND\d{6}[0-9<][MF<](\d{6})"#),
              let match = regex.firstMatch(in: compact, range: NSRange(compact.startIndex..., in: compact)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: compact)
        else { return nil }
        return mrzDateString(String(compact[range]))
    }

    // MARK: - Labeled biodata fields

    private static func parseLabeledFields(from lines: [String], joined: String, into result: inout ParsedPassport) {
        if result.lastName == nil,
           let last = labeledValue(in: joined, patterns: [
               #"(?i)surname[^\nA-Z]*\n\s*([A-Z][A-Z\s\-']{1,40})"#,
               #"(?i)sur[\W_]*name[^\nA-Z]*\n?\s*([A-Z]{2,20})"#,
           ])
        {
            result.lastName = DriverLicenseFormatting.personName(last)
        }

        if result.firstName == nil,
           let first = labeledValue(in: joined, patterns: [
               #"(?i)given\s*names?(?:\(s\))?[^\nA-Z]*\n?\s*([A-Z][A-Z\s\-'.]{1,60})"#,
               #"(?i)given\s*name[^\nA-Z]*\n?\s*([A-Z][A-Z\s\-'.]{1,60})"#,
           ])
        {
            let split = splitGivenNames(first)
            result.firstName = split.first
            result.middleName = result.middleName ?? split.middle
        }

        if result.passportNumber == nil,
           let number = labeledValue(in: joined, patterns: [
               #"(?i)passport\s*(?:no|number|\.?\s*no\.?)[^\nA-Z0-9]*([A-Z]\d{7})"#,
           ]) ?? firstCapture(in: joined, pattern: #"(?i)\b([A-Z]\d{7})\b"#)
        {
            result.passportNumber = normalizePassportNumber(number)
        }

        if result.nationality == nil,
           joined.uppercased().contains("INDIAN")
        {
            result.nationality = "IND"
        }

        if result.dateOfBirth == nil {
            result.dateOfBirth = labeledDate(in: joined, patterns: [
                #"(?i)date\s*of\s*birth[^\d]*(\d{2}\D?\d{2}\D?\d{4})"#,
                #"(?i)birth[^\d]*(\d{2}\D?\d{2}\D?\d{4})"#,
            ], preferEarliest: true)
        }

        if result.issueDate == nil {
            result.issueDate = labeledDate(in: joined, patterns: [
                #"(?i)date\s*of\s*issue[^\d]*(\d{2}\D?\d{2}\D?\d{4})"#,
                #"(?i)issue[^\d]*(\d{2}\D?\d{2}\D?\d{4})"#,
            ], preferEarliest: false)
        }

        if result.expiryDate == nil {
            result.expiryDate = labeledDate(in: joined, patterns: [
                #"(?i)date\s*of\s*expir(?:y|ation)[^\d]*(\d{2}\D?\d{2}\D?\d{4})"#,
                #"(?i)expir(?:y|ation)[^\d]*(\d{2}\D?\d{2}\D?\d{4})"#,
            ], preferEarliest: false)
        }

        if result.placeOfBirth == nil,
           let pob = labeledValue(in: joined, patterns: [
               #"(?i)place\s*of\s*birth[^\n]*\n?\s*([A-Z][A-Z,\s]{3,60})"#,
           ])
        {
            result.placeOfBirth = DriverLicenseFormatting.city(pob.replacingOccurrences(of: ",", with: ", "))
        }

        if result.placeOfIssue == nil,
           let poi = labeledValue(in: joined, patterns: [
               #"(?i)place\s*of\s*issue[^\n]*\n?\s*([A-Z][A-Z\s]{2,40})"#,
           ])
        {
            result.placeOfIssue = DriverLicenseFormatting.city(poi)
        }
    }

    private static func parseStandaloneNameLines(from lines: [String], into result: inout ParsedPassport) {
        guard result.lastName == nil || result.firstName == nil else { return }

        for (idx, line) in lines.enumerated() {
            let upper = line.uppercased()
            if upper.contains("SURNAME") || upper.contains("SUR NAM") {
                if result.lastName == nil, idx + 1 < lines.count {
                    let token = cleanNameToken(lines[idx + 1])
                    if ScanFieldValidator.isPlausibleNameComponent(token) {
                        result.lastName = DriverLicenseFormatting.personName(token)
                    }
                }
            }
            if upper.contains("GIVEN NAME") {
                if result.firstName == nil, idx + 1 < lines.count {
                    let token = cleanNameToken(lines[idx + 1])
                    if ScanFieldValidator.isPlausibleNameComponent(token) {
                        result.firstName = DriverLicenseFormatting.personName(token)
                    }
                }
            }
        }

        if result.lastName == nil || result.firstName == nil {
            for idx in 0 ..< lines.count - 1 {
                let upperA = lines[idx].uppercased()
                if upperA.contains("SURNAME") {
                    let last = cleanNameToken(lines[idx + 1])
                    if ScanFieldValidator.isPlausibleNameComponent(last) {
                        result.lastName = DriverLicenseFormatting.personName(last)
                    }
                }
                if upperA.contains("GIVEN NAME") {
                    let first = cleanNameToken(lines[idx + 1])
                    if ScanFieldValidator.isPlausibleNameComponent(first) {
                        result.firstName = DriverLicenseFormatting.personName(first)
                    }
                }
            }
        }

        if result.lastName == nil || result.firstName == nil {
            for idx in 0 ..< lines.count - 1 {
                let a = cleanNameToken(lines[idx])
                let b = cleanNameToken(lines[idx + 1])
                guard ScanFieldValidator.isPlausibleNameComponent(a),
                      ScanFieldValidator.isPlausibleNameComponent(b),
                      a == a.uppercased(), b == b.uppercased()
                else { continue }
                if result.lastName == nil { result.lastName = DriverLicenseFormatting.personName(a) }
                if result.firstName == nil { result.firstName = DriverLicenseFormatting.personName(b) }
                break
            }
        }
    }

    // MARK: - Helpers

    private static func splitGivenNames(_ raw: String) -> (first: String?, middle: String?) {
        let words = raw
            .replacingOccurrences(of: ".", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .map { DriverLicenseFormatting.personName(String($0)) }
            .filter { ScanFieldValidator.isPlausibleNameComponent($0) }
        guard let first = words.first else { return (nil, nil) }
        let middle = words.count > 1 ? words.dropFirst().joined(separator: " ") : nil
        return (first, middle?.isEmpty == true ? nil : middle)
    }

    private static func cleanNameToken(_ raw: String) -> String {
        var token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // OCR often suffixes names with ".0" or stray digits before punctuation is stripped.
        token = token.replacingOccurrences(of: #"\.\d+$"#, with: "", options: .regularExpression)
        token = token.replacingOccurrences(of: #"\d+$"#, with: "", options: .regularExpression)
        token = token
            .replacingOccurrences(of: #"^[^\p{L}]+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[^\p{L}\s\-'.]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = token.lowercased()
        if lower.contains("passport") || lower.contains("national") || lower.contains("indian") || lower.contains("republic") {
            return ""
        }
        return token
    }

    private static func normalizePassportNumber(_ raw: String) -> String {
        let cleaned = raw
            .replacingOccurrences(of: "<", with: "")
            .replacingOccurrences(of: "O", with: "0")
            .uppercased()
            .filter { $0.isLetter || $0.isNumber }
        guard cleaned.count >= 8 else { return cleaned }
        let letter = cleaned.first.map(String.init) ?? ""
        let digits = cleaned.dropFirst().filter(\.isNumber).prefix(7)
        return letter + digits
    }

    private static func isPlausibleIndianPassportNumber(_ raw: String) -> Bool {
        let normalized = normalizePassportNumber(raw)
        return normalized.range(of: #"^[A-Z]\d{7}$"#, options: .regularExpression) != nil
    }

    private static func labeledValue(in text: String, patterns: [String]) -> String? {
        for pattern in patterns {
            if let value = firstCapture(in: text, pattern: pattern) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    private static func labeledDate(in text: String, patterns: [String], preferEarliest: Bool) -> String? {
        var dates: [String] = []
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(text.startIndex..., in: text)
                regex.enumerateMatches(in: text, range: range) { match, _, _ in
                    guard let match, match.numberOfRanges > 1,
                          let r = Range(match.range(at: 1), in: text)
                    else { return }
                    if let normalized = normalizeIndianDate(String(text[r])) {
                        dates.append(normalized)
                    }
                }
            }
        }
        guard !dates.isEmpty else { return nil }
        if preferEarliest {
            return dates.sorted().first
        }
        return dates.sorted().last
    }

    private static func normalizeDates(in result: inout ParsedPassport) {
        result.dateOfBirth = result.dateOfBirth.flatMap(normalizeIndianDate)
        result.issueDate = result.issueDate.flatMap(normalizeIndianDate)
        result.expiryDate = result.expiryDate.flatMap(normalizeIndianDate)
    }

    private static func normalizeIndianDate(_ raw: String) -> String? {
        var s = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: "'", with: "/")
            .replacingOccurrences(of: ".", with: "/")

        // OCR like 02ID6/1990 — allow short letter runs between day/month parts.
        if let regex = try? NSRegularExpression(pattern: #"(\d{2})[^\d/]{0,4}(\d{1,2})[/\-](\d{2,4})"#),
           let match = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
           match.numberOfRanges > 3,
           let dR = Range(match.range(at: 1), in: s),
           let mR = Range(match.range(at: 2), in: s),
           let yR = Range(match.range(at: 3), in: s)
        {
            let dd = Int(s[dR]) ?? 0
            let mm = Int(s[mR]) ?? 0
            var yyyy = Int(s[yR]) ?? 0
            if yyyy < 100 {
                yyyy += yyyy >= 50 ? 1900 : 2000
            }
            if (1 ... 31).contains(dd), (1 ... 12).contains(mm), (1900 ... 2100).contains(yyyy) {
                return String(format: "%02d/%02d/%04d", dd, mm, yyyy)
            }
        }

        s = s
            .replacingOccurrences(of: "Q", with: "0")
            .replacingOccurrences(of: "O", with: "0")
            .replacingOccurrences(of: "I", with: "1")
            .replacingOccurrences(of: "L", with: "1")
            .replacingOccurrences(of: "S", with: "5")
            .replacingOccurrences(of: "D", with: "0")
            .replacingOccurrences(of: "B", with: "8")
            .replacingOccurrences(of: "Z", with: "2")

        let patterns = [
            #"^(\d{2})[/\-](\d{2})[/\-](\d{4})$"#,
            #"^(\d{2})(\d{2})(\d{4})$"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
                  match.numberOfRanges > 3,
                  let d = Range(match.range(at: 1), in: s),
                  let m = Range(match.range(at: 2), in: s),
                  let y = Range(match.range(at: 3), in: s)
            else { continue }
            return String(format: "%02d/%02d/%04d",
                          Int(s[d]) ?? 0,
                          Int(s[m]) ?? 0,
                          Int(s[y]) ?? 0)
        }
        return nil
    }

    private static func mrzDateString(_ yyMMdd: String) -> String? {
        let digits = yyMMdd.filter(\.isNumber)
        guard digits.count == 6 else { return nil }
        let i = digits.startIndex
        let yy = Int(digits[i ..< digits.index(i, offsetBy: 2)]) ?? 0
        let mm = Int(digits[digits.index(i, offsetBy: 2) ..< digits.index(i, offsetBy: 4)]) ?? 0
        let dd = Int(digits[digits.index(i, offsetBy: 4) ..< digits.index(i, offsetBy: 6)]) ?? 0
        let year = yy >= 50 ? 1900 + yy : 2000 + yy
        // Indian passports use DD/MM/YYYY on the biodata page.
        return String(format: "%02d/%02d/%04d", dd, mm, year)
    }

    private static func firstCapture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let r = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[r])
    }
}
