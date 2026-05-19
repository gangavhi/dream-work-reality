import Foundation

/// Parses passport biodata labels and ICAO TD3 MRZ lines (US, India, and other countries).
enum PassportParser {
    struct ParsedPassport {
        var firstName: String?
        var middleName: String?
        var lastName: String?
        var passportNumber: String?
        var nationality: String?
        var countryCode: String?
        var dateOfBirth: String?
        var issueDate: String?
        var expiryDate: String?
        var placeOfBirth: String?
    }

    static func parse(from text: String) -> ParsedPassport? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, isPassport(trimmed) else { return nil }

        let lines = trimmed
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map { OcrTextPostProcessor.cleanLine($0) }
            .filter { !$0.isEmpty }

        var result = ParsedPassport()
        parseMRZ(from: lines, into: &result)
        parseBiodataLabels(from: lines, joined: trimmed, into: &result)
        parseNameLines(from: lines, into: &result)

        guard result.lastName != nil
            || result.firstName != nil
            || result.passportNumber != nil
            || result.dateOfBirth != nil
        else { return nil }

        return result
    }

    static func suggestions(from text: String) -> [OcrFieldSuggestion] {
        guard let parsed = parse(from: text) else { return [] }

        let country = parsed.countryCode ?? "US"
        let context = DocumentFieldLabelContext(
            documentType: .passport,
            issuerRegion: nil,
            country: country
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

        add(ProfileFieldKey.displayName, display, 0.97)
        add(ProfileFieldKey.legalFirstName, first, 0.97)
        add(ProfileFieldKey.legalMiddleName, middle, 0.88)
        add(ProfileFieldKey.legalLastName, last, 0.97)
        add(ProfileFieldKey.passportNumber, parsed.passportNumber, 0.96)
        add(ProfileFieldKey.passportCountry, parsed.nationality, 0.93)
        add(ProfileFieldKey.passportExpiry, parsed.expiryDate, 0.94)
        add(ProfileFieldKey.dateOfBirth, parsed.dateOfBirth, 0.95)
        add(ProfileFieldKey.country, country, 0.9)

        if let pob = parsed.placeOfBirth {
            if pob.uppercased().contains("TEXAS") {
                add(ProfileFieldKey.state, "TX", 0.82)
            }
            add(ProfileFieldKey.city, pob, 0.75)
        }

        var seen = Set<String>()
        return ScanFieldValidator.filter(
            out.filter { seen.insert($0.profileKey).inserted },
            documentType: .passport
        )
    }

    static func isPassport(_ text: String) -> Bool {
        let upper = text.uppercased()
        if upper.contains("PASSPORT") { return true }
        if upper.contains("P<USA") || upper.contains("P<IND") { return true }
        if upper.range(of: #"P<[A-Z]{3}"#, options: .regularExpression) != nil { return true }
        if upper.range(of: #"[A-Z0-9<]{9}[0-9<][A-Z]{3}\d{6}"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    // MARK: - MRZ

    private static func parseMRZ(from lines: [String], into result: inout ParsedPassport) {
        for line in lines {
            let compact = line.replacingOccurrences(of: " ", with: "").uppercased()
            if compact.contains("P<") {
                parseMRZLine1(compact, into: &result)
            }
            if compact.range(of: #"^[A-Z0-9<]{9}\d[A-Z]{3}\d{6}"#, options: .regularExpression) != nil
                || compact.range(of: #"[A-Z0-9<]{9}\dIND\d{6}"#, options: .regularExpression) != nil
            {
                parseMRZLine2(compact, into: &result)
            }
        }
    }

    private static func parseMRZLine1(_ line: String, into result: inout ParsedPassport) {
        guard let start = line.range(of: "P<") else { return }
        var tail = String(line[start.upperBound...])
        guard tail.count >= 5 else { return }

        let issuer = String(tail.prefix(3))
        tail = String(tail.dropFirst(3))
        guard let split = tail.range(of: "<<") else { return }

        let lastRaw = String(tail[..<split.lowerBound]).replacingOccurrences(of: "<", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let givenRaw = String(tail[split.upperBound...]).replacingOccurrences(of: "<", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if result.countryCode == nil {
            result.countryCode = mapCountryCode(issuer)
            result.nationality = nationalityLabel(for: issuer)
        }
        if result.lastName == nil, ScanFieldValidator.isPlausibleNameComponent(lastRaw) {
            result.lastName = DriverLicenseFormatting.personName(lastRaw)
        }
        applyGivenNames(givenRaw, to: &result)
    }

    private static func parseMRZLine2(_ line: String, into result: inout ParsedPassport) {
        guard line.count >= 27 else { return }

        let passportRaw = String(line.prefix(9)).replacingOccurrences(of: "<", with: "")
        if result.passportNumber == nil, isPlausiblePassportNumber(passportRaw) {
            result.passportNumber = passportRaw
        }

        let nationality = String(line.dropFirst(10).prefix(3))
        if result.nationality == nil, !nationality.isEmpty {
            result.nationality = nationalityLabel(for: nationality)
            result.countryCode = mapCountryCode(nationality)
        }

        let dobStart = line.index(line.startIndex, offsetBy: 13)
        let dobEnd = line.index(dobStart, offsetBy: 6)
        if result.dateOfBirth == nil {
            result.dateOfBirth = mrzDateString(String(line[dobStart..<dobEnd]), countryCode: result.countryCode)
        }

        if line.count >= 27 {
            let expStart = line.index(line.startIndex, offsetBy: 21)
            let expEnd = line.index(expStart, offsetBy: 6)
            if result.expiryDate == nil {
                result.expiryDate = mrzDateString(String(line[expStart..<expEnd]), countryCode: result.countryCode)
            }
        }
    }

    // MARK: - Biodata labels

    private static func parseBiodataLabels(from lines: [String], joined: String, into result: inout ParsedPassport) {
        if result.lastName == nil,
           let last = labeledValue(in: joined, patterns: [
               #"(?i)surname(?:\s*/\s*[^\n]+)?[^\nA-Z]*\n\s*([A-Z][A-Z\s\-']{1,40})"#,
               #"(?i)surname[^\nA-Z]*\n\s*([A-Z]{2,20})"#,
           ])
        {
            result.lastName = DriverLicenseFormatting.personName(last)
        }

        if result.firstName == nil,
           let given = labeledValue(in: joined, patterns: [
               #"(?i)given\s*names?(?:\s*/\s*[^\n]+)?[^\nA-Z]*\n\s*([A-Z][A-Z\s\-']{1,60})"#,
               #"(?i)given\s*names?[^\nA-Z]*\n?\s*([A-Z][A-Z\s\-'.]{1,60})"#,
           ])
        {
            applyGivenNames(given, to: &result)
        }

        if result.passportNumber == nil,
           let number = labeledValue(in: joined, patterns: [
               #"(?i)passport\s*(?:no|number|\.?\s*no\.?)(?:\s*/\s*[^\n]+)?[^\nA-Z0-9]*([A-Z0-9]{8,9})"#,
           ])
        {
            result.passportNumber = number.uppercased()
        }

        if result.nationality == nil,
           let nat = labeledValue(in: joined, patterns: [
               #"(?i)nationality(?:\s*/\s*[^\n]+)?[^\nA-Z]*\n?\s*([A-Z][A-Z\s]{4,40})"#,
           ])
        {
            result.nationality = DriverLicenseFormatting.personName(nat)
            if nat.uppercased().contains("UNITED STATES") { result.countryCode = "US" }
            if nat.uppercased().contains("INDIA") || nat.uppercased() == "INDIAN" { result.countryCode = "IN" }
        }

        if result.dateOfBirth == nil {
            result.dateOfBirth = labeledDate(in: joined, patterns: [
                #"(?i)date\s*of\s*birth(?:\s*/\s*[^\n]+)?[^\dA-Z]*(\d{1,2}\s+[A-Z]{3}\s+\d{4})"#,
                #"(?i)date\s*of\s*birth[^\d]*(\d{2}\D?\d{2}\D?\d{4})"#,
            ], preferEarliest: true, countryCode: result.countryCode)
        }

        if result.issueDate == nil {
            result.issueDate = labeledDate(in: joined, patterns: [
                #"(?i)date\s*of\s*issue(?:\s*/\s*[^\n]+)?[^\dA-Z]*(\d{1,2}\s+[A-Z]{3}\s+\d{4})"#,
            ], preferEarliest: false, countryCode: result.countryCode)
        }

        if result.expiryDate == nil {
            result.expiryDate = labeledDate(in: joined, patterns: [
                #"(?i)date\s*of\s*expir(?:y|ation)(?:\s*/\s*[^\n]+)?[^\dA-Z]*(\d{1,2}\s+[A-Z]{3}\s+\d{4})"#,
                #"(?i)expir(?:y|ation)[^\d]*(\d{2}\D?\d{2}\D?\d{4})"#,
            ], preferEarliest: false, countryCode: result.countryCode)
        }

        if result.placeOfBirth == nil,
           let pob = labeledValue(in: joined, patterns: [
               #"(?i)place\s*of\s*birth(?:\s*/\s*[^\n]+)?[^\n]*\n?\s*([A-Z][A-Z,\.\s]{3,60})"#,
           ])
        {
            result.placeOfBirth = DriverLicenseFormatting.city(pob.replacingOccurrences(of: ",", with: ", "))
        }
    }

    private static func parseNameLines(from lines: [String], into result: inout ParsedPassport) {
        for (idx, line) in lines.enumerated() {
            let upper = line.uppercased()
            if upper.contains("SURNAME"), idx + 1 < lines.count {
                let token = cleanNameToken(lines[idx + 1])
                if result.lastName == nil, ScanFieldValidator.isPlausibleNameComponent(token) {
                    result.lastName = DriverLicenseFormatting.personName(token)
                }
            }
            if upper.contains("GIVEN NAME"), idx + 1 < lines.count {
                let token = cleanNameToken(lines[idx + 1])
                if result.firstName == nil, ScanFieldValidator.isPlausibleNameComponent(token) {
                    applyGivenNames(token, to: &result)
                }
            }
        }
    }

    // MARK: - Helpers

    private static func applyGivenNames(_ raw: String, to result: inout ParsedPassport) {
        let words = raw
            .replacingOccurrences(of: ".", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .map { DriverLicenseFormatting.personName(String($0)) }
            .filter { ScanFieldValidator.isPlausibleNameComponent($0) }
        guard let first = words.first else { return }
        result.firstName = result.firstName ?? first
        if words.count > 1 {
            result.middleName = result.middleName ?? words.dropFirst().joined(separator: " ")
        }
    }

    private static func cleanNameToken(_ raw: String) -> String {
        var token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        token = token.replacingOccurrences(of: #"\.\d+$"#, with: "", options: .regularExpression)
        token = token.replacingOccurrences(of: #"\d+$"#, with: "", options: .regularExpression)
        token = token
            .replacingOccurrences(of: #"^[^\p{L}]+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[^\p{L}\s\-'.]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = token.lowercased()
        if ["passport", "national", "indian", "republic", "united", "states", "america"].contains(where: { lower.contains($0) }) {
            return ""
        }
        return token
    }

    private static func mapCountryCode(_ issuer: String) -> String {
        switch issuer.uppercased() {
        case "USA": return "US"
        case "IND": return "IN"
        case "GBR", "UK": return "GB"
        case "CAN": return "CA"
        default: return issuer.uppercased()
        }
    }

    private static func nationalityLabel(for code: String) -> String {
        switch code.uppercased() {
        case "USA": return "United States of America"
        case "IND": return "IND"
        case "GBR": return "United Kingdom"
        default: return code.uppercased()
        }
    }

    private static func isPlausiblePassportNumber(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard trimmed.count >= 8, trimmed.count <= 9 else { return false }
        return trimmed.range(of: #"^[A-Z0-9]+$"#, options: .regularExpression) != nil
    }

    private static func mrzDateString(_ yyMMdd: String, countryCode: String?) -> String? {
        let digits = yyMMdd.filter(\.isNumber)
        guard digits.count == 6 else { return nil }
        let i = digits.startIndex
        let yy = Int(digits[i ..< digits.index(i, offsetBy: 2)]) ?? 0
        let mm = Int(digits[digits.index(i, offsetBy: 2) ..< digits.index(i, offsetBy: 4)]) ?? 0
        let dd = Int(digits[digits.index(i, offsetBy: 4) ..< digits.index(i, offsetBy: 6)]) ?? 0
        let year = yy >= 50 ? 1900 + yy : 2000 + yy
        if countryCode == "IN" {
            return String(format: "%02d/%02d/%04d", dd, mm, year)
        }
        return String(format: "%02d/%02d/%04d", mm, dd, year)
    }

    private static func parseTextDate(_ raw: String, countryCode: String?) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let monthMap = [
            "JAN": 1, "FEB": 2, "MAR": 3, "APR": 4, "MAY": 5, "JUN": 6,
            "JUL": 7, "AUG": 8, "SEP": 9, "OCT": 10, "NOV": 11, "DEC": 12,
        ]
        if let regex = try? NSRegularExpression(pattern: #"^(\d{1,2})\s+([A-Z]{3})\s+(\d{4})$"#),
           let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
           match.numberOfRanges > 3,
           let dR = Range(match.range(at: 1), in: trimmed),
           let mR = Range(match.range(at: 2), in: trimmed),
           let yR = Range(match.range(at: 3), in: trimmed),
           let month = monthMap[String(trimmed[mR])]
        {
            let day = Int(trimmed[dR]) ?? 0
            let year = Int(trimmed[yR]) ?? 0
            if countryCode == "IN" {
                return String(format: "%02d/%02d/%04d", day, month, year)
            }
            return String(format: "%02d/%02d/%04d", month, day, year)
        }

        var s = trimmed
            .replacingOccurrences(of: "Q", with: "0")
            .replacingOccurrences(of: "O", with: "0")
            .replacingOccurrences(of: "I", with: "1")
            .replacingOccurrences(of: "'", with: "/")
            .replacingOccurrences(of: ".", with: "/")
        if let regex = try? NSRegularExpression(pattern: #"^(\d{2})[/\-](\d{2})[/\-](\d{4})$"#),
           let match = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
           match.numberOfRanges > 3,
           let dR = Range(match.range(at: 1), in: s),
           let mR = Range(match.range(at: 2), in: s),
           let yR = Range(match.range(at: 3), in: s)
        {
            let a = Int(s[dR]) ?? 0
            let b = Int(s[mR]) ?? 0
            let y = Int(s[yR]) ?? 0
            if countryCode == "IN" {
                return String(format: "%02d/%02d/%04d", a, b, y)
            }
            return String(format: "%02d/%02d/%04d", a, b, y)
        }
        return nil
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

    private static func labeledDate(
        in text: String,
        patterns: [String],
        preferEarliest: Bool,
        countryCode: String?
    ) -> String? {
        var dates: [String] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            regex.enumerateMatches(in: text, range: range) { match, _, _ in
                guard let match, match.numberOfRanges > 1,
                      let r = Range(match.range(at: 1), in: text)
                else { return }
                if let normalized = parseTextDate(String(text[r]), countryCode: countryCode) {
                    dates.append(normalized)
                }
            }
        }
        guard !dates.isEmpty else { return nil }
        return preferEarliest ? dates.sorted().first : dates.sorted().last
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
