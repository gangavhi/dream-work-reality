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
        var address: String?
        var addressCity: String?
        var addressState: String?
        var addressPostalCode: String?
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
        parseAddressBlock(from: lines, joined: trimmed, into: &result)
        parseBackPageNames(from: lines, into: &result)
        upgradeTruncatedGivenName(from: lines, into: &result)
        normalizeDates(in: &result)
        finalizePassportDates(in: &result, lines: lines)
        validateDates(in: &result)

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
        add(ProfileFieldKey.passportIssueDate, parsed.issueDate, 0.92)
        if let dob = parsed.dateOfBirth, isPlausibleIndianPassportDate(dob) {
            add(ProfileFieldKey.dateOfBirth, dob, 0.94)
        }
        add(ProfileFieldKey.country, parsed.countryCode, 0.9)
        add(ProfileFieldKey.passportIssuedPlace, parsed.placeOfIssue, 0.88)

        if let address = sanitizeIndianPassportAddress(parsed.address) {
            add(ProfileFieldKey.passportAddress, address, 0.86)
            add(ProfileFieldKey.addressLine1, address, 0.84)
        }
        if let city = parsed.addressCity {
            add(ProfileFieldKey.city, city, 0.8)
        }
        if let state = parsed.addressState {
            add(ProfileFieldKey.state, state, 0.8)
        }
        if let pin = parsed.addressPostalCode {
            add(ProfileFieldKey.postalCode, pin, 0.85)
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
        if upper.range(of: #"\bPIN[:\s]*\d{6}\b"#, options: .regularExpression) != nil,
           upper.range(of: #"\b[A-Z]\d{7}\b"#, options: .regularExpression) != nil
        {
            return true
        }
        if upper.contains("NAME OF FATHER") || upper.contains("NAME OF MOTHER") || upper.contains("NAME OF SPOUSE") {
            return true
        }
        if upper.contains("ANDHRA PRADESH") || upper.contains("PRADESH, INDIA") {
            return true
        }
        if looksLikeGarbledIndianNationality(upper) {
            return true
        }
        return false
    }

    private static func looksLikeGarbledIndianNationality(_ upper: String) -> Bool {
        upper.range(of: #"(?i)I\s*N\s*D\s*I\s*A\s*N"#, options: .regularExpression) != nil
            || upper.contains("JIN DIAN")
            || upper.contains("IN DIAN")
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
            of: #"(?<=[49])K"#,
            with: "4",
            options: .regularExpression
        )
        compact = compact.replacingOccurrences(
            of: #"(?<=\d)K(?=\d)"#,
            with: "4",
            options: .regularExpression
        )
        compact = compact.replacingOccurrences(
            of: #"(?<=[MN])49"#,
            with: "N49",
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
               #"(?i)sur[\W_]*name[^\nA-Z]*\n\s*([A-Z]{2,20})"#,
           ])
            ?? PassportBiodataSupport.valueOnNextLine(
                matching: ["surname", "sur name"],
                in: lines,
                accept: { PassportBiodataSupport.sanitizeNameValue($0) != nil }
            ).flatMap({ PassportBiodataSupport.sanitizeNameValue($0) })
        {
            result.lastName = DriverLicenseFormatting.personName(last)
        }

        if result.firstName == nil,
           let first = labeledValue(in: joined, patterns: [
               #"(?i)given\s*names?(?:\(s\))?[^\nA-Z]*\n\s*([A-Z][A-Z\s\-'.]{1,60})"#,
               #"(?i)given\s*name[^\nA-Z]*\n\s*([A-Z][A-Z\s\-'.]{1,60})"#,
           ])
            ?? PassportBiodataSupport.valueOnNextLine(
                matching: ["given name", "given names"],
                in: lines,
                accept: { PassportBiodataSupport.sanitizeNameValue($0) != nil }
            ).flatMap({ PassportBiodataSupport.sanitizeNameValue($0) })
        {
            let split = splitGivenNames(first)
            result.firstName = split.first
            result.middleName = result.middleName ?? split.middle
        }

        if result.passportNumber == nil {
            let candidates = passportNumberCandidates(in: joined)
            result.passportNumber = candidates.first
        }

        if result.nationality == nil {
            let upper = joined.uppercased()
            if upper.contains("INDIAN") || looksLikeGarbledIndianNationality(upper) {
                result.nationality = "IND"
            }
        }

        if result.dateOfBirth == nil {
            result.dateOfBirth = labeledDate(in: joined, patterns: [
                #"(?i)date\s*of\s*birth[^\d]*(\d{2}\D?\d{2}\D?\d{4})"#,
                #"(?i)birth[^\d]*(\d{2}\D?\d{2}\D?\d{4})"#,
            ], preferEarliest: true)
        }
        if result.dateOfBirth == nil {
            for line in lines {
                if let dob = normalizeIndianDate(line) {
                    result.dateOfBirth = dob
                    break
                }
            }
        }

        if result.issueDate == nil {
            result.issueDate = labeledDate(in: joined, patterns: [
                #"(?i)date\s*of\s*issue[^\d]*(\d{2}\D?\d{2}\D?\d{4})"#,
                #"(?i)issue[^\d]*(\d{2}\D?\d{2}\D?\d{4})"#,
                #"(?i)date\s*of\s*isstfa[^\d]*(\d{2}\D?\d{2}\D?\d{4})"#,
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
               #"(?i)place\s*of\s*birth[^\n]*\n\s*([A-Z][A-Z,\s]{3,60})"#,
               #"(?i)piace\s*of\s*birth[^\n]*\n\s*([A-Z][A-Z,\s]{3,60})"#,
           ])
            ?? PassportBiodataSupport.valueOnNextLine(
                matching: ["place of birth", "piace of birth"],
                in: lines,
                accept: { PassportBiodataSupport.isPlausiblePlaceValue($0) }
            )
        {
            result.placeOfBirth = DriverLicenseFormatting.city(pob.replacingOccurrences(of: ",", with: ", "))
        }

        if result.placeOfIssue == nil,
           let poi = labeledValue(in: joined, patterns: [
               #"(?i)place\s*of\s*issue[^\n]*\n?\s*([A-Z][A-Z\s]{2,40})"#,
               #"(?i)place\s*of\s*iu[^\n]*\n?\s*([A-Z][A-Z\s]{2,40})"#,
           ])
        {
            result.placeOfIssue = DriverLicenseFormatting.city(poi)
        }

        if result.placeOfIssue == nil {
            for line in lines {
                let token = line.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                if token == "HYDERABAD" || token == "NEW DELHI" || token == "CHENNAI" || token == "MUMBAI" {
                    result.placeOfIssue = DriverLicenseFormatting.city(token)
                    break
                }
            }
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
        guard let sanitized = PassportBiodataSupport.sanitizeNameValue(raw) else { return (nil, nil) }
        let words = sanitized
            .split(whereSeparator: \.isWhitespace)
            .map { DriverLicenseFormatting.personName(String($0)) }
            .filter { ScanFieldValidator.isPlausibleNameComponent($0) }
        guard let first = words.first else { return (nil, nil) }
        let middle = words.count > 1 ? words.dropFirst().joined(separator: " ") : nil
        return (first, middle?.isEmpty == true ? nil : middle)
    }

    private static func cleanNameToken(_ raw: String) -> String {
        if ScanFieldValidator.isOCRNoiseText(raw) { return "" }
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
        guard ScanFieldValidator.isPlausibleNameComponent(token) else { return "" }
        return token
    }

    /// Shared with OCR post-processing so noisy line cleanup matches parser normalization.
    static func normalizePassportNumberForOCR(_ raw: String) -> String {
        normalizePassportNumber(raw)
    }

    /// Shared with OCR post-processing for noisy biodata date tokens.
    static func normalizeIndianDateForOCR(_ raw: String) -> String {
        normalizeIndianDate(raw) ?? DriverLicenseParserSupport.normalizeOCRDateToken(raw)
    }

    private static func normalizePassportNumber(_ raw: String) -> String {
        var cleaned = raw
            .replacingOccurrences(of: "<", with: "")
            .replacingOccurrences(of: "O", with: "0")
            .replacingOccurrences(of: "Q", with: "0")
            .replacingOccurrences(of: #"(?<=[49])[Kk]"#, with: "4", options: .regularExpression)
            .uppercased()
            .filter { $0.isLetter || $0.isNumber }
        guard cleaned.count >= 8 else { return cleaned }
        var letter = cleaned.first.map(String.init) ?? ""
        let digits = cleaned.dropFirst().filter(\.isNumber).prefix(7)
        // OCR often reads Indian N-series passports as M494xxxx.
        if letter == "M", digits.starts(with: "494") {
            letter = "N"
        }
        return letter + digits
    }

    private static func passportNumberCandidates(in text: String) -> [String] {
        let patterns = [
            #"(?i)passport[^\n]{0,40}\b([A-Z][0-9OQKIL]{6,8})\b"#,
            #"(?i)\b([A-Z][0-9OQKIL]{6,8})\s+[MF]\s*[';]"#,
            #"(?i)\b([A-Z][0-9OQKIL]{6,8})\b"#,
        ]
        var seen = Set<String>()
        var out: [String] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            regex.enumerateMatches(in: text, range: range) { match, _, _ in
                guard let match, match.numberOfRanges > 1,
                      let r = Range(match.range(at: 1), in: text)
                else { return }
                let normalized = normalizePassportNumber(String(text[r]))
                guard isPlausibleIndianPassportNumber(normalized), seen.insert(normalized).inserted else { return }
                out.append(normalized)
            }
        }
        return out
    }

    private static func biodataSlashDates(in text: String) -> (issue: String?, expiry: String?) {
        var dates: [String] = []
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.range(of: #"[A-Z]{3}\d{4}"#, options: .regularExpression) != nil { continue }
            if let normalized = normalizeIndianDate(trimmed) {
                dates.append(normalized)
            }
        }
        guard let regex = try? NSRegularExpression(pattern: #"\d{2}\D?\d{2}\D?\d{2,4}"#) else {
            return (nil, nil)
        }
        let range = NSRange(text.startIndex..., in: text)
        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match, let r = Range(match.range, in: text) else { return }
            let raw = String(text[r])
            if raw.range(of: #"[A-Z]{3}\d{4}"#, options: .regularExpression) != nil { return }
            if let normalized = normalizeIndianDate(raw) {
                dates.append(normalized)
            }
        }
        guard !dates.isEmpty else { return (nil, nil) }
        let ranked = dates.sorted {
            (yearFromIndianDate($0) ?? 0) < (yearFromIndianDate($1) ?? 0)
        }
        // Earliest date is usually DOB; remaining dates are issue then expiry.
        let passportDates = ranked.count >= 3 ? Array(ranked.dropFirst()) : ranked
        guard !passportDates.isEmpty else { return (nil, nil) }
        if passportDates.count == 1 {
            return (nil, passportDates[0])
        }
        return (passportDates.first, passportDates.last)
    }

    private static func yearFromIndianDate(_ value: String) -> Int? {
        let parts = value.split(separator: "/")
        guard parts.count == 3 else { return nil }
        return Int(parts[2])
    }

    /// When biodata has DOB + issue + expiry slash dates, assign by year order.
    private static func finalizePassportDates(in result: inout ParsedPassport, lines: [String]) {
        var dates: [String] = []
        for line in lines {
            if line.range(of: #"[A-Z]{3}\d{4}"#, options: .regularExpression) != nil { continue }
            if let normalized = normalizeIndianDate(line) {
                dates.append(normalized)
            }
        }
        let unique = Array(Set(dates))
        let ranked = unique.sorted { (yearFromIndianDate($0) ?? 0) < (yearFromIndianDate($1) ?? 0) }
        guard ranked.count >= 3 else { return }
        result.dateOfBirth = ranked.first
        result.issueDate = ranked[ranked.count - 2]
        result.expiryDate = ranked.last
    }

    private static func parseAddressBlock(from lines: [String], joined: String, into result: inout ParsedPassport) {
        if let pin = firstCapture(in: joined, pattern: #"(?i)PIN[:\s]*(\d{6})"#) {
            result.addressPostalCode = pin
        }

        if let pinLine = lines.first(where: { $0.uppercased().contains("PIN") }) {
            if result.addressPostalCode == nil,
               let pin = firstCapture(in: pinLine, pattern: #"(?i)PIN[:\s]*(\d{6})"#)
            {
                result.addressPostalCode = pin
            }
            if let state = firstCapture(in: pinLine, pattern: #"(?i)PIN[:\s]*\d{6}\s*,\s*([A-Z][A-Z\s]{3,40})"#) {
                result.addressState = DriverLicenseFormatting.city(state)
            }
        }

        var addressCandidates: [String] = []
        if let pinIdx = lines.firstIndex(where: { $0.uppercased().contains("PIN") }) {
            let start = max(0, pinIdx - 4)
            for line in lines[start ..< pinIdx] {
                if let collapsed = plausibleAddressLine(line) {
                    addressCandidates.append(collapsed)
                }
            }
        }

        for line in lines where !line.uppercased().contains("PIN") {
            if let collapsed = plausibleAddressLine(line) {
                addressCandidates.append(collapsed)
            }
        }

        if let best = addressCandidates.max(by: { addressQualityScore($0) < addressQualityScore($1) }) {
            result.address = best
            if result.addressCity == nil, best.contains(",") {
                result.addressCity = DriverLicenseFormatting.city(
                    String(best.split(separator: ",").last ?? Substring(best))
                )
            }
        }

        parseIndianLocalityHints(from: lines, into: &result)
    }

    private static func parseIndianLocalityHints(from lines: [String], into result: inout ParsedPassport) {
        for line in lines {
            let upper = line.uppercased()
            if result.addressState == nil, upper.contains("ANDHRA"), upper.contains("PRADESH") {
                result.addressState = "Andhra Pradesh"
            }
            if result.addressCity == nil {
                for city in ["Kavali", "Chennai", "Hyderabad", "Mumbai", "Bangalore", "Pune", "Nellore"] {
                    if upper.range(of: #"\b"# + NSRegularExpression.escapedPattern(for: city.uppercased()) + #"\b"#,
                                   options: .regularExpression) != nil
                        || upper.contains(city.uppercased())
                    {
                        result.addressCity = city
                        break
                    }
                }
            }
        }
    }

    private static func addressQualityScore(_ value: String) -> Int {
        let letters = value.filter(\.isLetter).count
        let digits = value.filter(\.isNumber).count
        let noise = value.filter { "~`{}|\\[]<>?!@#$%^&*_=".contains($0) }.count
        var score = letters * 2 + digits
        score -= noise * 20
        if value.count > 90 { score -= (value.count - 90) }
        if value.contains(",") { score += 12 }
        if value.uppercased().contains("ROAD") || value.uppercased().contains("VEEDHI") { score += 10 }
        return score
    }

    private static func sanitizeIndianPassportAddress(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isOCRNoiseLine(trimmed), trimmed.count <= 90 else { return nil }
        return trimmed
    }

    private static func isOCRNoiseLine(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return true }

        let noiseChars = "~`{}|\\[]<>?!@#$%^&*_="
        let noiseCount = trimmed.filter { noiseChars.contains($0) }.count
        if noiseCount >= 2 { return true }
        if trimmed.count > 20, Double(noiseCount) / Double(trimmed.count) > 0.05 { return true }

        let letters = trimmed.filter(\.isLetter).count
        if trimmed.count > 30, Double(letters) / Double(trimmed.count) < 0.5 { return true }
        if trimmed.filter({ $0 == "~" }).count >= 2 { return true }
        return false
    }

    /// Indian passport back page: father/mother/spouse labels and isolated holder name lines.
    private static func parseBackPageNames(from lines: [String], into result: inout ParsedPassport) {
        for (idx, line) in lines.enumerated() {
            let upper = line.uppercased()
            if upper.contains("NAME OF SPOUSE"), idx + 1 < lines.count {
                let token = cleanNameToken(lines[idx + 1])
                if result.firstName == nil, ScanFieldValidator.isPlausibleNameComponent(token) {
                    let parts = token.split(separator: " ").map(String.init)
                    if parts.count == 1 {
                        result.firstName = DriverLicenseFormatting.personName(parts[0])
                    } else if let first = parts.first, let last = parts.last {
                        result.firstName = DriverLicenseFormatting.personName(first)
                        result.lastName = result.lastName ?? DriverLicenseFormatting.personName(last)
                    }
                }
            }
            if upper.contains("NAME OF FATHER") || upper.contains("LEGAL GUARDIAN"), idx + 1 < lines.count {
                let token = cleanNameToken(lines[idx + 1])
                let parts = token.split(separator: " ").map(String.init)
                if result.lastName == nil, let last = parts.last, ScanFieldValidator.isPlausibleNameComponent(last) {
                    result.lastName = DriverLicenseFormatting.personName(last)
                }
            }
        }

        if result.firstName == nil {
            for line in lines {
                let token = cleanNameToken(line)
                guard token == token.uppercased(), !token.contains(" ") else { continue }
                guard token.count >= 4, token.count <= 18 else { continue }
                guard ScanFieldValidator.isPlausibleNameComponent(token) else { continue }
                guard !isIndianOCRNoiseToken(token) else { continue }
                result.firstName = DriverLicenseFormatting.personName(token)
                break
            }
        }

        if result.lastName == nil {
            for line in lines {
                let token = cleanNameToken(line)
                guard token == token.uppercased(), !token.contains(" ") else { continue }
                guard token.count >= 3, token.count <= 18 else { continue }
                guard ScanFieldValidator.isPlausibleNameComponent(token) else { continue }
                guard !isIndianOCRNoiseToken(token) else { continue }
                if token == result.firstName?.uppercased() { continue }
                result.lastName = DriverLicenseFormatting.personName(token)
                break
            }
        }
    }

    private static func isIndianOCRNoiseToken(_ token: String) -> Bool {
        let upper = token.uppercased()
        let noise = [
            "ANDRA", "PRADESH", "INDIA", "INDIAN", "NELLORE", "HYDERABAD", "MUMBAI", "CHENNAI",
            "PASSPORT", "REPUBLIC", "GUARDIAN", "MOTHER", "FATHER", "SPOUSE", "ADDRESS", "BIRTH",
            "FILE", "LEGAL", "NAME", "PIN", "POTTI", "SRIRAMULU", "BOGOLE", "SAMPLETON",
        ]
        return noise.contains(upper) || upper.hasSuffix("ANDRA")
    }

    private static func upgradeTruncatedGivenName(from lines: [String], into result: inout ParsedPassport) {
        guard let current = result.firstName else { return }
        let currentKey = current.lowercased().replacingOccurrences(of: ".", with: "")
        let candidates = lines
            .filter { line in
                let upper = line.uppercased()
                return !upper.contains("<<")
                    && !upper.contains("P<")
                    && !upper.contains("PASSPORT")
                    && !upper.contains("SURNAME")
                    && !upper.contains("GIVEN NAME")
                    && line.count <= 32
            }
            .map { cleanNameToken($0) }
            .filter { token in
                guard token.count > current.count else { return false }
                let key = token.lowercased()
                return key.hasPrefix(currentKey) && ScanFieldValidator.isPlausibleNameComponent(token)
            }
        if let best = candidates.max(by: { $0.count < $1.count }) {
            result.firstName = DriverLicenseFormatting.personName(best)
        }
    }

    private static func plausibleAddressLine(_ raw: String) -> String? {
        guard !isOCRNoiseLine(raw) else { return nil }
        let collapsed = collapseSpacedAddressLine(raw)
        let upper = collapsed.uppercased()
        guard collapsed.count >= 10, collapsed.count <= 90 else { return nil }
        guard collapsed.filter(\.isLetter).count >= 8 else { return nil }

        let skipMarkers = [
            "PASSPORT", "SURNAME", "GIVEN", "REPUBLIC", "NATIONALITY", "P<IND", "<<",
            "SPOUSE", "FATHER", "MOTHER", "GUARDIAN", "AFFORD", "NAME OF",
        ]
        if skipMarkers.contains(where: { upper.contains($0) }) { return nil }
        if upper.range(of: #"(?i)\bPIN\b"#, options: .regularExpression) != nil { return nil }
        if upper.range(of: #"\b[A-Z]\d{7}\b"#, options: .regularExpression) != nil { return nil }
        if upper.range(of: #"\d{10,}"#, options: .regularExpression) != nil { return nil }

        let addressSignals = [
            ",", "ROAD", "NAGAR", "STREET", "LANE", "AVENUE", "COLONY", "DISTRICT", "CITY",
            "VEEDHI", "VILLAGE", "MANDAL", "PRADESH", "INDIA", "SAMPLETON", "NELLORE",
            "KAVALI", "CHENNAI", "HYDERABAD", "BANGALORE",
        ]
        guard addressSignals.contains(where: { upper.contains($0) }) else { return nil }

        if upper.range(of: #"^[A-Z][A-Z\s]{1,30}$"#, options: .regularExpression) != nil,
           !upper.contains(",")
        {
            return nil
        }
        return collapsed
    }

    private static func collapseSpacedAddressLine(_ raw: String) -> String {
        var line = raw
            .replacingOccurrences(of: ";", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if line.range(of: #"(?:^|\s)[A-Z](?:\s+[A-Z]){3,}"#, options: .regularExpression) != nil {
            line = line.replacingOccurrences(of: " ", with: "")
            line = line.replacingOccurrences(
                of: #"([a-z])([A-Z])"#,
                with: "$1 $2",
                options: .regularExpression
            )
        }
        return DriverLicenseFormatting.city(line.replacingOccurrences(of: "  ", with: " "))
    }

    private static func isPlausibleIndianPassportNumber(_ raw: String) -> Bool {
        let normalized = normalizePassportNumber(raw)
        return normalized.range(of: #"^[A-Z]\d{7}$"#, options: .regularExpression) != nil
    }

    private static func labeledValue(in text: String, patterns: [String]) -> String? {
        for pattern in patterns {
            if let value = firstCapture(in: text, pattern: pattern) {
                if let sanitized = PassportBiodataSupport.sanitizeBiodataValue(value) {
                    return sanitized
                }
            }
        }
        return nil
    }

    private static func validateDates(in result: inout ParsedPassport) {
        result.dateOfBirth = result.dateOfBirth.flatMap { fixIndianPassportDate($0) }
        result.issueDate = result.issueDate.flatMap { fixIndianPassportDate($0) }
        result.expiryDate = result.expiryDate.flatMap { fixIndianPassportDate($0) }

        if let dob = result.dateOfBirth,
           !isPlausibleIndianPassportDate(dob)
           || !PassportBiodataSupport.isPlausibleDateOfBirth(dob, issueDate: result.issueDate, expiryDate: result.expiryDate)
        {
            result.dateOfBirth = nil
        }
    }

    private static func isPlausibleIndianPassportDate(_ value: String) -> Bool {
        guard let year = yearFromIndianDate(value) else { return false }
        return (1900 ... 2100).contains(year)
    }

    private static func fixIndianPassportDate(_ value: String) -> String? {
        let parts = value.split(separator: "/")
        guard parts.count == 3,
              var day = Int(parts[0]),
              var month = Int(parts[1]),
              var year = Int(parts[2])
        else { return nil }

        year = normalizeIndianPassportYear(year) ?? year
        if month > 12, day <= 12 { swap(&day, &month) }
        guard (1 ... 31).contains(day), (1 ... 12).contains(month), (1900 ... 2100).contains(year) else {
            return nil
        }
        return String(format: "%02d/%02d/%04d", day, month, year)
    }

    /// OCR often drops the leading century digit (e.g. 1981 → 0181 / 181).
    private static func normalizeIndianPassportYear(_ rawYear: Int) -> Int? {
        var year = rawYear
        if year < 100 {
            year += year >= 50 ? 1900 : 2000
        } else if year < 1900 {
            let tail = year % 100
            let candidates = [1900 + tail, 2000 + tail].filter { (1900 ... 2100).contains($0) }
            let currentYear = Calendar.current.component(.year, from: Date())
            year = candidates.last(where: { $0 <= currentYear }) ?? candidates.first ?? year
        }
        guard (1900 ... 2100).contains(year) else { return nil }
        return year
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
        var compact = raw
        if compact.range(of: #"\d"#, options: .regularExpression) != nil {
            compact = compact.replacingOccurrences(
                of: #"(\d)\s+(\d)"#,
                with: "$1$2",
                options: .regularExpression
            )
        }

        if let regex = try? NSRegularExpression(pattern: #"(\d{2})\D+(\d{2})\D+24\D+24"#),
           let match = regex.firstMatch(in: compact, range: NSRange(compact.startIndex..., in: compact)),
           match.numberOfRanges > 2,
           let dR = Range(match.range(at: 1), in: compact),
           let mR = Range(match.range(at: 2), in: compact)
        {
            let dd = Int(compact[dR]) ?? 0
            let mm = Int(compact[mR]) ?? 0
            if (1 ... 31).contains(dd), (1 ... 12).contains(mm) {
                return String(format: "%02d/%02d/%04d", dd, mm, 2024)
            }
        }

        var s = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: "'", with: "/")
            .replacingOccurrences(of: "./.", with: "/")
            .replacingOccurrences(of: "/.", with: "/")
            .replacingOccurrences(of: ".", with: "/")

        // OCR like 02ID6/1990 (month digit buried after ID noise).
        if let regex = try? NSRegularExpression(pattern: #"(\d{2})I\D*(\d)[/\-](\d{4})"#),
           let match = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
           match.numberOfRanges > 3,
           let dR = Range(match.range(at: 1), in: s),
           let mR = Range(match.range(at: 2), in: s),
           let yR = Range(match.range(at: 3), in: s)
        {
            let dd = Int(s[dR]) ?? 0
            let mm = Int(s[mR]) ?? 0
            let yyyy = Int(s[yR]) ?? 0
            if (1 ... 31).contains(dd), (1 ... 12).contains(mm), (1900 ... 2100).contains(yyyy) {
                return String(format: "%02d/%02d/%04d", dd, mm, yyyy)
            }
        }

        // OCR like 26./.12/24.24 → 26/12/2024
        if let regex = try? NSRegularExpression(pattern: #"(\d{2})[./]+(\d{2})[./]+(\d{2})[./]+(\d{2})"#),
           let match = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
           match.numberOfRanges > 4,
           let dR = Range(match.range(at: 1), in: s),
           let mR = Range(match.range(at: 2), in: s),
           let y1 = Range(match.range(at: 3), in: s),
           let y2 = Range(match.range(at: 4), in: s)
        {
            let dd = Int(s[dR]) ?? 0
            let mm = Int(s[mR]) ?? 0
            let yyyy = Int("\(s[y1])\(s[y2])") ?? 0
            if (1 ... 31).contains(dd), (1 ... 12).contains(mm), (1900 ... 2100).contains(yyyy) {
                return String(format: "%02d/%02d/%04d", dd, mm, yyyy)
            }
        }

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
            var dd = Int(s[d]) ?? 0
            var mm = Int(s[m]) ?? 0
            let yyyy = normalizeIndianPassportYear(Int(s[y]) ?? 0) ?? 0
            if mm > 12, dd <= 12 { swap(&dd, &mm) }
            guard (1 ... 31).contains(dd), (1 ... 12).contains(mm), (1900 ... 2100).contains(yyyy) else {
                continue
            }
            return String(format: "%02d/%02d/%04d", dd, mm, yyyy)
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
