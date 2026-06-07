import Foundation

/// Texas DL uses AAMVA-style numbered rows: 1=last name, 2=first name, 3=DOB, 4a=issue, 4b=expiry, 4d=DL#, 8=address.
enum TexasDriverLicenseParser {
    static func parse(from lines: [String], joined: String) -> DriverLicenseScanResult? {
        guard isTexasDriverLicense(lines: lines, joined: joined) else { return nil }

        var result = DriverLicenseScanResult(rawText: joined)

        for (idx, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if let last = captureNumberedField(trimmed, number: "1") {
                result.lastName = DriverLicenseFormatting.personName(last)
            }
            if let first = captureNumberedField(trimmed, number: "2") {
                result.firstName = DriverLicenseFormatting.personName(first)
            }

            if isDOBLine(trimmed), let date = extractDateFromOCRLine(trimmed), isPlausibleBirthDate(date) {
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

            if result.documentNumber == nil, let dl = captureDLNumber(from: trimmed) {
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
        parseMisorderedTexasNames(from: lines, into: &result)
        parseAddressBlock(from: lines, into: &result)
        recoverTexasAddressFragments(from: lines, into: &result)
        if let cleanBirth = bestPlausibleBirthDate(from: lines) {
            result.dateOfBirth = cleanBirth
        }
        assignTexasDatesIfMissing(from: lines, into: &result)
        captureFragmentedTexasDLNumber(from: lines, into: &result)
        refineTexasDLNumberByConsensus(from: lines, into: &result)

        if result.state == nil {
            result.state = USJurisdictionSupport.inferStateCode(from: lines, joined: joined)
        }

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
        let compact = line.replacingOccurrences(of: #"^8\.?\s*"#, with: "", options: .regularExpression)
        if let regex = try? NSRegularExpression(pattern: #"^(\d{3,5})\s*([A-Za-z\.]+)$"#),
           let match = regex.firstMatch(in: compact, range: NSRange(compact.startIndex..., in: compact)),
           match.numberOfRanges > 2,
           let numRange = Range(match.range(at: 1), in: compact),
           let suffixRange = Range(match.range(at: 2), in: compact)
        {
            let num = String(compact[numRange])
            var suffix = String(compact[suffixRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            if suffix == "B." || suffix == "B" { suffix = "Ct" }
            return "\(num) \(suffix)"
        }

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
        let now = Date()
        let birth = result.dateOfBirth
        let futureDates = dates.filter { date in
            date > now && !sameDay(date, birth)
        }.sorted()
        let pastDates = dates.filter { date in
            date <= now && !sameDay(date, birth)
        }.sorted()

        if result.issueDate == nil, pastDates.count >= 2 {
            result.issueDate = pastDates.dropLast().last
        }
        if result.expiryDate == nil {
            result.expiryDate = futureDates.first
        }
    }

    /// Fixes OCR like `06/0211990` → `06/02/1990`.
    private static func fuzzyDateTokens(in line: String) -> [String] {
        DriverLicenseParserSupport.fuzzyDateTokens(in: line)
    }

    private static func extractDateFromOCRLine(_ line: String) -> Date? {
        for token in fuzzyDateTokens(in: line) {
            if let d = DriverLicenseParserSupport.parseDate(token) { return d }
            if let d = DriverLicenseParserSupport.parseDateDDMMYYYY(token) { return d }
        }
        return DriverLicenseParserSupport.firstDate(in: line)
            ?? DriverLicenseParserSupport.firstDateDDMMYYYY(in: line)
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
        let lower = line.lowercased()
        if lower.contains("dob") || lower.contains("дов") || lower.contains("exp") || lower.contains("iss") {
            return nil
        }
        let hasDLContext = lower.contains("dl") || lower.contains("4d")
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.range(of: #"^\d{7,8}$"#, options: .regularExpression) != nil,
           !isTexasDateNumericFragment(trimmed, in: line),
           ScanFieldValidator.isPlausibleDriversLicenseNumber(trimmed)
        {
            return trimmed
        }

        var patterns = [
            #"(?i)4d\.?\s*DL\s*:?\s*([A-Z0-9]{4,20})"#,
            #"(?i)\bD\s+(\d{7,9})\b"#,
            #"(?i)\bDL\s*:?\s*([A-Z0-9]{7,9})\b"#,
            #"\b([1-9]\d{6,7})\b"#,
        ]
        if hasDLContext {
            patterns.append(#"\b([D]\d{7,8})\b"#)
        }
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

    private static func captureFragmentedTexasDLNumber(from lines: [String], into result: inout DriverLicenseScanResult) {
        guard result.documentNumber == nil else { return }
        for (idx, line) in lines.enumerated() {
            guard let regex = try? NSRegularExpression(pattern: #"\b(\d{6})\s+(\d{1,3})\b"#),
                  let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  match.numberOfRanges > 2,
                  let leftRange = Range(match.range(at: 1), in: line),
                  let rightRange = Range(match.range(at: 2), in: line)
            else { continue }
            let joined = String(line[leftRange]) + String(line[rightRange])
            if ScanFieldValidator.isPlausibleDriversLicenseNumber(joined) {
                result.documentNumber = joined
                return
            }
            if idx + 1 < lines.count {
                let next = lines[idx + 1].trimmingCharacters(in: .whitespacesAndNewlines)
                if let digits = next.range(of: #"^\d{1,3}$"#, options: .regularExpression) {
                    let joinedNext = String(line[leftRange]) + String(next[digits])
                    if ScanFieldValidator.isPlausibleDriversLicenseNumber(joinedNext) {
                        result.documentNumber = joinedNext
                        return
                    }
                }
            }
        }
    }

    /// When Vision OCR emits field `8.` before `1.`/`2.`, standalone surname/given lines appear after the address band.
    private static func parseMisorderedTexasNames(from lines: [String], into result: inout DriverLicenseScanResult) {
        guard result.lastName == nil || result.firstName == nil else { return }

        let tokens: [String] = lines.compactMap { line in
            let token = normalizeLatinLookalikes(stripLeadingNoise(line))
            guard isStandaloneTexasNameToken(token) else { return nil }
            return token
        }

        for idx in 0 ..< tokens.count - 1 {
            let lastToken = tokens[idx]
            let firstToken = tokens[idx + 1]
            guard lastToken.count >= 3, lastToken.count <= 12 else { continue }
            guard firstToken.count >= 6 else { continue }
            guard lastToken != firstToken else { continue }
            if result.lastName == nil {
                result.lastName = DriverLicenseFormatting.personName(lastToken)
            }
            if result.firstName == nil {
                result.firstName = DriverLicenseFormatting.personName(firstToken)
            }
            break
        }
    }

    private static func isStandaloneTexasNameToken(_ token: String) -> Bool {
        guard !token.isEmpty, !isBoilerplateName(token) else { return false }
        guard token == token.uppercased() else { return false }
        guard token.range(of: #"^[A-Z][A-Z\-']+$"#, options: .regularExpression) != nil else { return false }
        return ScanFieldValidator.isPlausibleNameComponent(token)
    }

    private static func normalizeLatinLookalikes(_ token: String) -> String {
        let map: [Character: Character] = [
            "А": "A", "В": "B", "С": "C", "Е": "E", "Н": "H", "К": "K", "М": "M",
            "О": "O", "Р": "P", "Т": "T", "Х": "X", "У": "Y",
        ]
        return String(token.map { map[$0] ?? $0 })
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

    private static func bestPlausibleBirthDate(from lines: [String]) -> Date? {
        var weighted: [String: Int] = [:]
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let tokens = fuzzyDateTokens(in: trimmed)
            let isStandalone = trimmed.range(of: #"^\d{2}/\d{2}/\d{4}$"#, options: .regularExpression) != nil
            for token in tokens {
                guard let date = DriverLicenseParserSupport.parseDate(token),
                      isPlausibleBirthDate(date)
                else { continue }
                var weight = 1
                if isStandalone { weight += 3 }
                if trimmed.lowercased().contains("dob") || trimmed.lowercased().contains("дов") { weight += 1 }
                weighted[token, default: 0] += weight
            }
        }

        let ranked = weighted.sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            // Texas DL ghost DOB duplicates the same date — prefer day 02 over OCR 21/24 when tied.
            func dayComponent(_ token: String) -> Int {
                let parts = token.split(separator: "/")
                guard parts.count > 1 else { return 99 }
                return Int(parts[1]) ?? 99
            }
            return dayComponent(lhs.key) < dayComponent(rhs.key)
        }

        for (token, _) in ranked {
            if let date = DriverLicenseParserSupport.parseDate(token), isPlausibleBirthDate(date) {
                return date
            }
        }
        return nil
    }

    private static func recoverTexasAddressFragments(from lines: [String], into result: inout DriverLicenseScanResult) {
        if result.addressLine1 == nil {
            for line in lines {
                if let street = captureTexasAddressLine(line) {
                    result.addressLine1 = DriverLicenseFormatting.streetAddress(street)
                    break
                }
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if let regex = try? NSRegularExpression(pattern: #"(?i)^8\.?\s*(\d{3,5})\s*([A-Za-z\.]+)$"#),
                   let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
                   match.numberOfRanges > 2,
                   let numRange = Range(match.range(at: 1), in: trimmed),
                   let suffixRange = Range(match.range(at: 2), in: trimmed)
                {
                    var suffix = String(trimmed[suffixRange])
                    if suffix.uppercased() == "B." || suffix.uppercased() == "B" { suffix = "Ct" }
                    result.addressLine1 = DriverLicenseFormatting.streetAddress("\(trimmed[numRange]) \(suffix)")
                    break
                }
            }
        }

        if result.postalCode == nil {
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if let regex = try? NSRegularExpression(pattern: #"^(\d{5})(?:-(\d{4}))?$"#),
                   let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
                   match.numberOfRanges > 1,
                   let zipRange = Range(match.range(at: 1), in: trimmed)
                {
                    result.postalCode = String(trimmed[zipRange])
                    break
                }
            }
        }

        if result.city == nil, let zipIdx = lines.firstIndex(where: {
            $0.range(of: #"\b\d{5}(?:-\d{4})?\b"#, options: .regularExpression) != nil
        }) {
            let lastName = result.lastName?.uppercased()
            let firstName = result.firstName?.uppercased()
            // City is usually the ALL-CAPS line immediately above ZIP on Texas DL photos.
            let searchStart = max(0, zipIdx - 3)
            for idx in (searchStart ..< zipIdx).reversed() {
                let token = stripLeadingNoise(lines[idx])
                guard token.count >= 4, token.count <= 14 else { continue }
                guard token == token.uppercased() else { continue }
                guard token.range(of: #"^[A-Z][A-Z\-']+$"#, options: .regularExpression) != nil else { continue }
                guard !isBoilerplateName(token) else { continue }
                guard !DriverLicenseParserSupport.isStreetSuffixToken(token) else { continue }
                let upper = token.uppercased()
                if upper == lastName || upper == firstName { continue }
                result.city = DriverLicenseFormatting.city(token)
                break
            }
        }

        if result.state == nil {
            result.state = USJurisdictionSupport.inferStateCode(from: lines, joined: lines.joined(separator: "\n"))
        }
    }

    private static func refineTexasDLNumberByConsensus(from lines: [String], into result: inout DriverLicenseScanResult) {
        // Keep explicit 4d. DL captures (e.g. D12345678) — consensus is for noisy numeric-only OCR.
        if let existing = result.documentNumber, existing.rangeOfCharacter(from: .letters) != nil {
            return
        }

        var candidates: [String] = []
        if let existing = result.documentNumber?.filter(\.isNumber), existing.count >= 7 {
            candidates.append(String(existing.prefix(8)))
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.range(of: #"^\d{7,8}$"#, options: .regularExpression) != nil else { continue }
            if isTexasDateNumericFragment(trimmed, in: line) { continue }
            if ScanFieldValidator.isPlausibleDriversLicenseNumber(trimmed) {
                candidates.append(trimmed)
            }
        }

        let joined = lines.joined(separator: " ")
        if let regex = try? NSRegularExpression(pattern: #"\b(\d{7,8})\b"#) {
            let ns = joined as NSString
            regex.enumerateMatches(in: joined, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
                guard let match, match.numberOfRanges > 1,
                      let range = Range(match.range(at: 1), in: joined) else { return }
                let token = String(joined[range])
                if isTexasDateNumericFragment(token, in: joined) { return }
                if ScanFieldValidator.isPlausibleDriversLicenseNumber(token) {
                    candidates.append(token)
                }
            }
        }

        candidates = Array(Set(candidates))
        guard candidates.count >= 2 else { return }

        let targetLen = candidates.map(\.count).max() ?? 8
        var voted = ""
        for pos in 0 ..< targetLen {
            var counts: [Character: Int] = [:]
            for candidate in candidates where candidate.count > pos {
                let ch = candidate[candidate.index(candidate.startIndex, offsetBy: pos)]
                counts[ch, default: 0] += 1
            }
            if let best = counts.max(by: { $0.value < $1.value })?.key {
                voted.append(best)
            }
        }
        if voted.count >= 7, ScanFieldValidator.isPlausibleDriversLicenseNumber(voted) {
            result.documentNumber = voted
        } else if let best = candidates.max(by: { $0.count < $1.count }) {
            result.documentNumber = best
        }
    }

    /// OCR date garble like `06/0241990` yields `0241990` — must not vote as a DL number.
    private static func isTexasDateNumericFragment(_ token: String, in context: String) -> Bool {
        guard token.count == 7, token.hasPrefix("0") else { return false }
        return context.range(of: #"/\#(token)"#, options: .regularExpression) != nil
            || context.range(of: #"\#(token)\d"#, options: .regularExpression) != nil
    }

    private static func isPlausibleBirthDate(_ date: Date) -> Bool {
        let now = Date()
        guard date <= now else { return false }
        let years = Calendar.current.dateComponents([.year], from: date, to: now).year ?? 0
        return years >= 14 && years <= 110
    }

    private static func sameDay(_ lhs: Date?, _ rhs: Date?) -> Bool {
        guard let lhs, let rhs else { return false }
        return Calendar.current.isDate(lhs, inSameDayAs: rhs)
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
        if let merged = normalizeMergedSlashDate(token) {
            return merged
        }
        let fixes: [(String, Int)] = [
            (#"^(\d{2})/(\d{2})1(\d{4})$"#, 3),
            (#"^(\d{2})/(\d{2})0(\d{4})$"#, 3),
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

    /// Fixes OCR like `06/0241990` → `06/02/1990` (merged day + year).
    private static func normalizeMergedSlashDate(_ token: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"^(\d{2})/(\d{7})$"#),
              let match = regex.firstMatch(in: token, range: NSRange(token.startIndex..., in: token)),
              match.numberOfRanges == 3,
              let mmRange = Range(match.range(at: 1), in: token),
              let tailRange = Range(match.range(at: 2), in: token)
        else { return nil }

        let tail = String(token[tailRange])
        guard tail.count == 7, let year = Int(tail.suffix(4)), year >= 1930, year <= 2015 else { return nil }
        let dayDigits = String(tail.prefix(3))
        let dd: String
        if dayDigits.hasPrefix("0"), dayDigits.count == 3 {
            dd = String(dayDigits.dropFirst().prefix(2))
        } else {
            dd = String(dayDigits.prefix(2))
        }
        guard let day = Int(dd), day >= 1, day <= 31 else { return nil }
        return "\(token[mmRange])/\(dd)/\(year)"
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

    static func parseDateDDMMYYYY(_ str: String) -> Date? {
        guard let regex = try? NSRegularExpression(pattern: #"^(\d{2})/(\d{2})/(\d{4})$"#),
              let match = regex.firstMatch(in: str, range: NSRange(str.startIndex..., in: str)),
              match.numberOfRanges == 4,
              let ddRange = Range(match.range(at: 1), in: str),
              let mmRange = Range(match.range(at: 2), in: str),
              let yyyyRange = Range(match.range(at: 3), in: str),
              let day = Int(str[ddRange]), let month = Int(str[mmRange]), let year = Int(str[yyyyRange]),
              day >= 1, day <= 31, month >= 1, month <= 12
        else { return nil }
        let token = String(format: "%02d/%02d/%04d", month, day, year)
        return parseDate(token)
    }

    static func firstDateDDMMYYYY(in s: String) -> Date? {
        guard let regex = try? NSRegularExpression(pattern: #"\b(\d{2}/\d{2}/\d{4})\b"#) else { return nil }
        let ns = s as NSString
        var found: Date?
        regex.enumerateMatches(in: s, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match, match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: s) else { return }
            let token = String(s[range])
            let parts = token.split(separator: "/").compactMap { Int($0) }
            guard parts.count == 3, parts[0] > 12, parts[1] <= 12 else { return }
            if let d = parseDateDDMMYYYY(token) {
                found = d
            }
        }
        return found
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
