import Foundation

/// Texas DL uses AAMVA-style numbered rows: 1=last name, 2=first name, 3=DOB, 4a=issue, 4b=expiry, 4d=DL#, 8=address.
enum TexasDriverLicenseParser {
    static func parse(from lines: [String], joined: String) -> DriverLicenseScanResult? {
        guard isTexasDriverLicense(lines: lines, joined: joined) else { return nil }

        var result = DriverLicenseScanResult(rawText: joined)
        result.state = "TX"

        for (idx, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if let last = captureNumberedField(trimmed, number: "1") {
                result.lastName = DriverLicenseFormatting.personName(last)
            }
            if let first = captureNumberedField(trimmed, number: "2") {
                result.firstName = DriverLicenseFormatting.personName(first)
            }

            if isDOBLine(trimmed), let date = extractDateFromOCRLine(trimmed) {
                result.dateOfBirth = date
            }

            if isIssueLine(trimmed), let date = extractDateFromOCRLine(trimmed) {
                result.issueDate = date
            } else if isIssueLine(trimmed), idx + 1 < lines.count,
                      let date = extractDateFromOCRLine(lines[idx + 1])
            {
                result.issueDate = date
            }

            if isExpiryLine(trimmed), let date = extractDateFromOCRLine(trimmed) {
                result.expiryDate = date
            }

            if let dl = captureDLNumber(from: trimmed) {
                result.documentNumber = dl
            }

            if let street = captureTexasAddressLine(trimmed) {
                result.addressLine1 = DriverLicenseFormatting.streetAddress(street)
            }

            if let csz = DriverLicenseParserSupport.parseCityStateZip(trimmed) {
                result.city = DriverLicenseFormatting.city(csz.city)
                result.state = csz.state
                result.postalCode = DriverLicenseFormatting.zip5(csz.zip)
            }
        }

        parseStandaloneTexasNames(from: lines, into: &result)
        parseAddressBlock(from: lines, into: &result)
        assignTexasDatesIfMissing(from: lines, into: &result)

        if result.firstName != nil || result.lastName != nil {
            result.fullName = DriverLicenseFormatting.displayName(
                first: result.firstName,
                middle: result.middleName,
                last: result.lastName
            )
        }

        if let first = result.firstName {
            result.firstName = expandFirstName(from: lines, current: first, lastName: result.lastName ?? "")
        }

        if result.firstName != nil || result.lastName != nil {
            result.fullName = DriverLicenseFormatting.displayName(
                first: result.firstName,
                middle: result.middleName,
                last: result.lastName
            )
        }

        guard result.lastName != nil
            || result.firstName != nil
            || result.dateOfBirth != nil
            || result.documentNumber != nil
            || result.addressLine1 != nil
        else { return nil }

        return result
    }

    private static func isTexasDriverLicense(lines: [String], joined: String) -> Bool {
        let upper = joined.uppercased()
        if upper.contains("TEXAS") || upper.contains("TEXASS") { return true }
        if upper.contains("DRIVER LICENSE") && upper.contains("4D") { return true }
        return lines.contains { $0.range(of: #"(?i)4d\.?\s*DL"#, options: .regularExpression) != nil }
    }

    private static func isDOBLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        if lower.contains("dob") || lower.contains("дов") || lower.contains("bdate") { return true }
        // OCR sometimes reads "3." as Cyrillic "з."
        return line.range(of: #"(?i)^[34zз]\.?\s"#, options: .regularExpression) != nil
            && line.range(of: #"\d{2}[/\-]\d"#, options: .regularExpression) != nil
    }

    private static func isIssueLine(_ line: String) -> Bool {
        line.range(of: #"(?i)4a\.?\s*Iss"#, options: .regularExpression) != nil
    }

    private static func isExpiryLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        if line.range(of: #"(?i)4b\.?\s*Exp"#, options: .regularExpression) != nil { return true }
        if lower.contains("exp") || lower.contains("expir") { return true }
        // Garbled OCR "4b" variants
        return line.range(of: #"(?i)^4[^a].*?\d{2}/\d{2}/\d{4}"#, options: .regularExpression) != nil
    }

    private static func captureTexasAddressLine(_ line: String) -> String? {
        let pattern = #"(?i)^8\.?\s+(\d+\s+[A-Za-z0-9\s\.\#\-]+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: line)
        else { return nil }
        return String(line[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// OCR often drops the "1." / "2." prefixes — find consecutive standalone name lines (TX: last, then first).
    private static func parseStandaloneTexasNames(from lines: [String], into result: inout DriverLicenseScanResult) {
        func isNameToken(_ token: String) -> Bool {
            guard !token.isEmpty, !isBoilerplateName(token) else { return false }
            guard !DriverLicenseParserSupport.isStreetSuffixToken(token) else { return false }
            guard token.range(of: #"^[A-Za-z\-']+$"#, options: .regularExpression) != nil else { return false }
            return ScanFieldValidator.isPlausibleNameComponent(token)
        }

        let start = lines.firstIndex(where: { line in
            let upper = line.uppercased()
            return upper.contains("DRIVER") || upper.contains("LICENSE") || upper.contains("TEXAS")
        }) ?? 0
        let end = lines.firstIndex(where: { line in
            line.range(of: #"(?i)^8\.?\s"#, options: .regularExpression) != nil
                || DriverLicenseParserSupport.parseCityStateZip(line) != nil
                || DriverLicenseParserSupport.looksLikeStreetNameLine(line)
        }) ?? lines.count
        let upperBound = min(max(end, start + 1), lines.count)

        for idx in start ..< upperBound - 1 {
            if isDOBLine(lines[idx]) || isDOBLine(lines[idx + 1]) { continue }
            if lines[idx].range(of: #"^\d+\s+\S+"#, options: .regularExpression) != nil { continue }

            let lastToken = stripLeadingNoise(lines[idx])
            let firstToken = stripLeadingNoise(lines[idx + 1])
            guard isNameToken(lastToken), isNameToken(firstToken) else { continue }
            if result.lastName == nil {
                result.lastName = DriverLicenseFormatting.personName(lastToken)
            }
            if result.firstName == nil {
                result.firstName = DriverLicenseFormatting.personName(firstToken)
            }
            break
        }
    }

    private static func expandFirstName(from lines: [String], current: String, lastName: String) -> String {
        let upperCurrent = current.uppercased()
        var best = current

        for (idx, line) in lines.enumerated() {
            let token = stripLeadingNoise(line)
            let upperToken = token.uppercased()

            if (upperToken == "SREE" || upperToken == "SRI"), idx + 1 < lines.count {
                let next = stripLeadingNoise(lines[idx + 1]).uppercased()
                if next == upperCurrent || next.hasSuffix(upperCurrent) {
                    let combined = token + stripLeadingNoise(lines[idx + 1])
                    if combined.count > best.count {
                        best = combined
                    }
                }
                continue
            }

            guard !token.isEmpty, !isBoilerplateName(token) else { continue }
            guard token.range(of: #"^[A-Za-z][A-Za-z\-']*$"#, options: .regularExpression) != nil else { continue }
            guard ScanFieldValidator.isPlausibleNameComponent(token) else { continue }

            if upperToken != lastName.uppercased(),
               upperToken.hasSuffix(upperCurrent),
               token.count > best.count
            {
                best = token
            }
        }

        return DriverLicenseFormatting.personName(best)
    }

    private static func stripLeadingNoise(_ line: String) -> String {
        line
            .replacingOccurrences(of: #"^[^\p{L}]+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func assignTexasDatesIfMissing(from lines: [String], into result: inout DriverLicenseScanResult) {
        var dates: [Date] = []
        for line in lines {
            for token in fuzzyDateTokens(in: line) {
                if let d = DriverLicenseParserSupport.parseDate(token) {
                    dates.append(d)
                }
            }
        }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        dates = Array(Set(dates.map { utc.startOfDay(for: $0) }))

        if result.dateOfBirth == nil {
            result.dateOfBirth = dates
                .filter { isPlausibleBirthDate($0) }
                .max()
        }
        if result.issueDate == nil {
            result.issueDate = dates.first { d in
                let y = Calendar.current.component(.year, from: d)
                return y >= 2020 && y <= 2025
            }
        }
        if result.expiryDate == nil {
            result.expiryDate = dates.first { d in
                let y = Calendar.current.component(.year, from: d)
                return y >= 2026 && y <= 2035
            }
        }
    }

    /// Fixes OCR like `06/0211990` → `06/02/1990`.
    private static func fuzzyDateTokens(in line: String) -> [String] {
        DriverLicenseParserSupport.fuzzyDateTokens(in: line)
    }

    private static func extractDateFromOCRLine(_ line: String) -> Date? {
        for token in fuzzyDateTokens(in: line) {
            if let d = DriverLicenseParserSupport.parseDate(token) { return d }
        }
        return DriverLicenseParserSupport.firstDate(in: line)
    }

    private static func captureNumberedField(_ line: String, number: String) -> String? {
        let pattern = "^\(number)\\.?\\s+([A-Za-z][A-Za-z\\-'\\.\\s]+)$"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: line)
        else { return nil }

        let value = String(line[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !isBoilerplateName(value) else { return nil }
        return value
    }

    private static func captureDLNumber(from line: String) -> String? {
        let patterns = [
            #"(?i)4d\.?\s*DL\s*:?\s*([A-Z0-9]{4,20})"#,
            #"(?i)\bD\s+(\d{7,9})\b"#,
            #"(?i)\bDL\s*:?\s*([A-Z0-9]{7,9})\b"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: line)
            else { continue }
            let candidate = String(line[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if ScanFieldValidator.isPlausibleDriversLicenseNumber(candidate) {
                return candidate
            }
        }
        return nil
    }

    private static func parseAddressBlock(from lines: [String], into result: inout DriverLicenseScanResult) {
        if result.addressLine1 != nil, result.city != nil { return }

        guard let addrIdx = lines.firstIndex(where: {
            $0.range(of: #"(?i)^8\.?\s*Address"#, options: .regularExpression) != nil
        }) else { return }

        var streetParts: [String] = []
        for offset in 1 ... 4 {
            let idx = addrIdx + offset
            guard idx < lines.count else { break }
            let line = lines[idx].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if line.range(of: #"^\d+[a-z]?\."#, options: .regularExpression) != nil { break }
            if let csz = DriverLicenseParserSupport.parseCityStateZip(line) {
                result.city = DriverLicenseFormatting.city(csz.city)
                result.state = csz.state
                result.postalCode = DriverLicenseFormatting.zip5(csz.zip)
                break
            }
            if line.range(of: #"^\d+\s+\S+"#, options: .regularExpression) != nil || streetParts.isEmpty {
                streetParts.append(line)
            }
        }
        if result.addressLine1 == nil, !streetParts.isEmpty {
            result.addressLine1 = DriverLicenseFormatting.streetAddress(streetParts.joined(separator: " "))
        }
    }

    private static func isPlausibleBirthDate(_ date: Date) -> Bool {
        let now = Date()
        guard date <= now else { return false }
        let years = Calendar.current.dateComponents([.year], from: date, to: now).year ?? 0
        return years >= 14 && years <= 110
    }

    private static func isBoilerplateName(_ value: String) -> Bool {
        let lower = value.lowercased()
        return [
            "driver", "license", "texas", "texass", "director", "limited", "term", "none", "eno",
            "class", "rest", "hgt", "sex", "eyes", "blk",
        ].contains(lower)
    }
}

enum DriverLicenseFormatting {
    static func personName(_ raw: String) -> String {
        raw.split(whereSeparator: { $0.isWhitespace })
            .map { part in
                let s = String(part)
                guard !s.isEmpty else { return s }
                return s.prefix(1).uppercased() + s.dropFirst().lowercased()
            }
            .joined(separator: " ")
    }

    static func displayName(first: String?, middle: String?, last: String?) -> String? {
        let parts = [first, middle, last]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    static func streetAddress(_ raw: String) -> String {
        raw.split(separator: " ")
            .enumerated()
            .map { index, part -> String in
                let word = String(part)
                if index == 0, word.allSatisfy(\.isNumber) { return word }
                switch word.uppercased() {
                case "CT": return "Ct"
                case "ST": return "St"
                case "DR": return "Dr"
                case "AVE": return "Ave"
                case "BLVD": return "Blvd"
                case "RD": return "Rd"
                case "LN": return "Ln"
                default:
                    return word.prefix(1).uppercased() + word.dropFirst().lowercased()
                }
            }
            .joined(separator: " ")
    }

    static func city(_ raw: String) -> String {
        personName(raw)
    }

    static func zip5(_ raw: String) -> String {
        let digits = raw.filter(\.isNumber)
        guard digits.count >= 5 else { return raw }
        return String(digits.prefix(5))
    }
}

/// Shared helpers used by Texas parser and DriverLicenseParser.
enum DriverLicenseParserSupport {
    static func firstDate(in s: String) -> Date? {
        for token in fuzzyDateTokens(in: s) {
            if let d = parseDate(token) { return d }
        }
        return nil
    }

    static func fuzzyDateTokens(in line: String) -> [String] {
        var out: [String] = []
        let patterns = [
            #"\d{2}/\d{2}/\d{4}"#,
            #"\d{2}/\d{2}1\d{4}"#,
            #"\d{2}/\d{2}\d{4}"#,
            #"\d{2}/\d{2,3}/\d{4}"#,
            #"\d{2}/\d{2,3}\d{4}"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let ns = line as NSString
            regex.enumerateMatches(in: line, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
                guard let match else { return }
                let token = normalizeOCRDateToken(ns.substring(with: match.range))
                if !out.contains(token) {
                    out.append(token)
                }
            }
        }
        return out
    }

    /// Fixes OCR like `06/0211990` → `06/02/1990` or `06/021990` → `06/02/1990`.
    static func normalizeOCRDateToken(_ raw: String) -> String {
        var token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let fixes: [(String, Int)] = [
            (#"^(\d{2})/(\d{2})1(\d{4})$"#, 3),
            (#"^(\d{2})/(\d{2})(\d{4})$"#, 3),
        ]
        for (pattern, groups) in fixes {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: token, range: NSRange(token.startIndex..., in: token)),
                  match.numberOfRanges == groups + 1,
                  let mm = Range(match.range(at: 1), in: token),
                  let dd = Range(match.range(at: 2), in: token),
                  let yyyy = Range(match.range(at: 3), in: token)
            else { continue }
            token = "\(token[mm])/\(token[dd])/\(token[yyyy])"
            break
        }
        return token
    }

    static func parseDate(_ str: String) -> Date? {
        let fmts = ["MM/dd/yyyy", "M/d/yyyy", "MM-d-yyyy", "M-d-yyyy", "yyyy-MM-dd"]
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        for f in fmts {
            df.dateFormat = f
            if let d = df.date(from: str) { return d }
        }
        return nil
    }

    struct CityStateZip {
        let city: String
        let state: String
        let zip: String
        let street: String?
    }

    private static let streetSuffixTokens: Set<String> = [
        "st", "street", "rd", "road", "ave", "avenue", "dr", "drive", "ln", "lane",
        "blvd", "boulevard", "way", "ct", "court", "pl", "place", "cir", "circle",
        "trl", "trail", "pkwy", "parkway", "hwy", "highway",
    ]

    static func isStreetSuffixToken(_ token: String) -> Bool {
        streetSuffixTokens.contains(token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    /// Detects address fragments without a leading house number (e.g. OCR garble `MARLY COURT`).
    static func looksLikeStreetNameLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.range(of: #"^\d+\s+\S"#, options: .regularExpression) != nil { return true }
        if trimmed.range(of: #"(?i)^\d+\.\s*(?:Rest|De|End|DD)\b"#, options: .regularExpression) != nil {
            return true
        }
        let words = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        if words.count == 1 {
            return isStreetSuffixToken(words[0])
        }
        if words.contains(where: isStreetSuffixToken) { return true }
        return MappedFieldValueValidator.looksLikeStreetAddress(trimmed)
    }

    static func parseCityStateZip(_ line: String) -> CityStateZip? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = trimmed.replacingOccurrences(of: ",", with: " ")
        let pattern = #"(?i)^(.+?)\s+([A-Za-z]{2})\s+(\d{5})(?:-(\d{4}))?\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)),
              match.numberOfRanges >= 4,
              let cityRange = Range(match.range(at: 1), in: cleaned),
              let stateRange = Range(match.range(at: 2), in: cleaned),
              let zipRange = Range(match.range(at: 3), in: cleaned)
        else { return nil }

        let state = String(cleaned[stateRange]).uppercased()
        guard ScanFieldValidator.isPlausibleUSState(state) else { return nil }
        return CityStateZip(
            city: String(cleaned[cityRange]).trimmingCharacters(in: .whitespacesAndNewlines),
            state: state,
            zip: String(cleaned[zipRange]),
            street: nil
        )
    }
}
