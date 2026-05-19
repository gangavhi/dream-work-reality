import Foundation

/// Authoritative name resolution from OCR text — Texas DL uses LAST then FIRST.
enum PersonNameResolver {
    struct ResolvedName {
        var first: String
        var middle: String?
        var last: String

        var display: String {
            DriverLicenseFormatting.displayName(first: first, middle: middle, last: last) ?? ""
        }
    }

    static func apply(
        to suggestions: [OcrFieldSuggestion],
        ocrText: String,
        documentType: ScannedDocumentType = .other
    ) -> [OcrFieldSuggestion] {
        if IndianPassportParser.isIndianPassport(ocrText) {
            let indian = IndianPassportParser.suggestions(from: ocrText)
            if !indian.isEmpty {
                return mergePassportSuggestions(indian, into: suggestions)
            }
        }
        if PassportParser.isPassport(ocrText) {
            let passport = PassportParser.suggestions(from: ocrText)
            if !passport.isEmpty {
                return mergePassportSuggestions(passport, into: suggestions)
            }
        }

        let resolved = resolve(from: ocrText, documentType: documentType)
            ?? resolveFromSuggestions(suggestions)
        guard let resolved else {
            return NameFieldReconciler.reconcile(suggestions)
        }

        var byKey = Dictionary(uniqueKeysWithValues: suggestions.map { ($0.profileKey, $0) })
        let confidence = max(
            byKey[ProfileFieldKey.displayName]?.confidenceScore ?? 0.95,
            byKey[ProfileFieldKey.legalFirstName]?.confidenceScore ?? 0.95,
            byKey[ProfileFieldKey.legalLastName]?.confidenceScore ?? 0.95,
            0.96
        )

        func upsert(_ key: String, _ fallbackLabel: String, _ value: String) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            byKey[key] = OcrFieldSuggestion(
                profileKey: key,
                label: byKey[key]?.label ?? fallbackLabel,
                value: DriverLicenseFormatting.personName(trimmed),
                confidence: "High",
                confidenceScore: confidence
            )
        }

        upsert(ProfileFieldKey.legalFirstName, "Legal first name", resolved.first)
        upsert(ProfileFieldKey.legalLastName, "Legal last name", resolved.last)
        if let middle = resolved.middle, !middle.isEmpty {
            upsert(ProfileFieldKey.legalMiddleName, "Legal middle name", middle)
        }
        upsert(ProfileFieldKey.displayName, "Full name", resolved.display)

        return ProfileSchema.sortSuggestions(Array(byKey.values))
    }

    static func resolve(from ocrText: String, documentType: ScannedDocumentType) -> ResolvedName? {
        let lines = ocrText
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map { OcrTextPostProcessor.cleanLine($0) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }

        let joined = lines.joined(separator: "\n")
        let isTexas = isTexasDriverLicenseContext(lines: lines, joined: joined)
        let isDL = isTexas
            || documentType == .driversLicense
            || documentType == .stateId
            || joined.uppercased().contains("DRIVER LICENSE")

        if isDL {
            if let texas = resolveTexasNames(from: lines) { return texas }
            if let dl = resolveFromDriverLicenseParse(ocrText) { return dl }
        }

        if joined.uppercased().contains("SOCIAL SECURITY"), let ssn = resolveSSNNames(from: lines) {
            return ssn
        }

        if let comma = resolveCommaFormat(from: lines) { return comma }
        return nil
    }

    // MARK: - Texas

    private static func resolveTexasNames(from lines: [String]) -> ResolvedName? {
        var last: String?
        var first: String?

        for line in lines {
            if let value = captureTexasNumberedField(line, number: "1") {
                last = DriverLicenseFormatting.personName(value)
            }
            if let value = captureTexasNumberedField(line, number: "2") {
                first = DriverLicenseFormatting.personName(value)
            }
        }

        if first == nil || last == nil {
            if let pair = resolveTexasConsecutiveLines(from: lines) {
                if last == nil { last = pair.last }
                if first == nil { first = pair.first }
            }
        }

        if first == nil || last == nil {
            if let pair = resolveTexasSingleLine(from: lines) {
                if last == nil { last = pair.last }
                if first == nil { first = pair.first }
            }
        }

        guard var resolvedFirst = first, var resolvedLast = last else { return nil }
        guard ScanFieldValidator.isPlausibleNameComponent(resolvedFirst),
              ScanFieldValidator.isPlausibleNameComponent(resolvedLast)
        else { return nil }

        resolvedFirst = expandFirstName(from: lines, current: resolvedFirst, lastName: resolvedLast)

        return ResolvedName(first: resolvedFirst, middle: nil, last: resolvedLast)
    }

    private static func nameBandRange(in lines: [String]) -> Range<Int> {
        let start = lines.firstIndex(where: { line in
            let upper = line.uppercased()
            return upper.contains("DRIVER") || upper.contains("LICENSE") || upper.contains("TEXAS")
        }) ?? 0

        let end = lines.firstIndex(where: { line in
            line.range(of: #"(?i)^8\.?\s"#, options: .regularExpression) != nil
                || DriverLicenseParserSupport.parseCityStateZip(line) != nil
        }) ?? lines.count

        return start ..< min(max(end, start + 1), lines.count)
    }

    private static func searchEndForNames(in lines: [String], from start: Int) -> Int {
        lines.firstIndex(where: { line in
            line.range(of: #"(?i)^8\.?\s"#, options: .regularExpression) != nil
                || DriverLicenseParserSupport.parseCityStateZip(line) != nil
        }) ?? lines.count
    }

    private static func resolveTexasConsecutiveLines(from lines: [String]) -> ResolvedName? {
        let start = lines.firstIndex(where: { line in
            let upper = line.uppercased()
            return upper.contains("DRIVER") || upper.contains("LICENSE") || upper.contains("TEXAS")
        }) ?? 0
        let end = searchEndForNames(in: lines, from: start)

        for idx in start ..< min(end, lines.count - 1) {
            if isTexasDOBLine(lines[idx]) || isTexasDOBLine(lines[idx + 1]) { continue }
            if lineLooksLikeAddress(lines[idx]) || lineLooksLikeAddress(lines[idx + 1]) { continue }

            let lastToken = stripNameNoise(lines[idx])
            let firstToken = stripNameNoise(lines[idx + 1])
            guard isNameToken(lastToken), isNameToken(firstToken) else { continue }
            return ResolvedName(
                first: DriverLicenseFormatting.personName(firstToken),
                middle: nil,
                last: DriverLicenseFormatting.personName(lastToken)
            )
        }
        return nil
    }

    /// Two-word line on Texas DL: native order is LAST FIRST (`SMITH JANE`).
    private static func resolveTexasSingleLine(from lines: [String]) -> ResolvedName? {
        let band = nameBandRange(in: lines)
        for idx in band {
            let line = stripNameNoise(lines[idx])
            let words = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard words.count == 2 else { continue }
            guard words.allSatisfy(isNameToken) else { continue }

            let w0 = words[0]
            let w1 = words[1]
            // Shorter token first → Texas LAST-FIRST (`SMITH JANE`).
            // Longer token first → OCR read display order (`JANE SMITH`).
            if w0.count <= w1.count {
                return ResolvedName(
                    first: DriverLicenseFormatting.personName(w1),
                    middle: nil,
                    last: DriverLicenseFormatting.personName(w0)
                )
            }
            return ResolvedName(
                first: DriverLicenseFormatting.personName(w0),
                middle: nil,
                last: DriverLicenseFormatting.personName(w1)
            )
        }
        return nil
    }

    /// OCR may split a long first name into fragments (e.g. `ALEX` + `ANDER`) or truncate suffixes.
    private static func expandFirstName(from lines: [String], current: String, lastName: String) -> String {
        let upperCurrent = current.uppercased()
        var best = current

        for (idx, line) in lines.enumerated() {
            let token = stripNameNoise(line)
            let upperToken = token.uppercased()
            guard isNameToken(token) else { continue }

            if upperToken != lastName.uppercased(),
               upperToken.hasSuffix(upperCurrent),
               token.count > best.count
            {
                best = token
            }

            if (upperToken == "SREE" || upperToken == "SRI"),
               idx + 1 < lines.count
            {
                let next = stripNameNoise(lines[idx + 1]).uppercased()
                if next == upperCurrent || next.hasSuffix(upperCurrent) {
                    let combined = token + stripNameNoise(lines[idx + 1])
                    if combined.count > best.count {
                        best = combined
                    }
                }
            }
        }

        return DriverLicenseFormatting.personName(best)
    }

    // MARK: - Other sources

    private static func resolveFromDriverLicenseParse(_ ocrText: String) -> ResolvedName? {
        let scan = DriverLicenseParser.parseWithoutGenericNames(ocrText)
        guard let first = scan.firstName?.trimmingCharacters(in: .whitespacesAndNewlines),
              let last = scan.lastName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !first.isEmpty, !last.isEmpty,
              ScanFieldValidator.isPlausibleNameComponent(first),
              ScanFieldValidator.isPlausibleNameComponent(last)
        else { return nil }

        return ResolvedName(
            first: DriverLicenseFormatting.personName(first),
            middle: scan.middleName.map { DriverLicenseFormatting.personName($0) },
            last: DriverLicenseFormatting.personName(last)
        )
    }

    private static func resolveSSNNames(from lines: [String]) -> ResolvedName? {
        for line in lines {
            if let name = captureGroup(
                in: line,
                pattern: #"(?i)^(?:THIS\s+NUMBER\s+HAS\s+BEEN\s+ESTABLISHED\s+FOR)\s*(.+)$"#
            ), isPlausibleNameLine(name) {
                return resolvedFromFirstLastLine(name)
            }
        }

        for idx in 0 ..< lines.count - 1 {
            let firstLine = stripNameNoise(lines[idx])
            let secondLine = stripNameNoise(lines[idx + 1])
            guard isNameToken(firstLine), isNameToken(secondLine) else { continue }
            return ResolvedName(
                first: DriverLicenseFormatting.personName(firstLine),
                middle: nil,
                last: DriverLicenseFormatting.personName(secondLine)
            )
        }
        return nil
    }

    private static func resolveCommaFormat(from lines: [String]) -> ResolvedName? {
        for line in lines {
            guard line.contains(",") else { continue }
            let split = NameFieldReconciler.splitDisplayName(line)
            guard !split.first.isEmpty, !split.last.isEmpty else { continue }
            return ResolvedName(first: split.first, middle: split.middle, last: split.last)
        }
        return nil
    }

    private static func resolveFromSuggestions(_ suggestions: [OcrFieldSuggestion]) -> ResolvedName? {
        let byKey = Dictionary(uniqueKeysWithValues: suggestions.map { ($0.profileKey, $0.value) })
        let first = byKey[ProfileFieldKey.legalFirstName]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let middle = byKey[ProfileFieldKey.legalMiddleName]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = byKey[ProfileFieldKey.legalLastName]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !first.isEmpty, !last.isEmpty else { return nil }
        return ResolvedName(
            first: DriverLicenseFormatting.personName(first),
            middle: middle.flatMap { $0.isEmpty ? nil : DriverLicenseFormatting.personName($0) },
            last: DriverLicenseFormatting.personName(last)
        )
    }

    private static func resolvedFromFirstLastLine(_ line: String) -> ResolvedName? {
        let split = NameFieldReconciler.splitDisplayName(line)
        guard !split.first.isEmpty, !split.last.isEmpty else { return nil }
        return ResolvedName(first: split.first, middle: split.middle, last: split.last)
    }

    // MARK: - Helpers

    private static func isTexasDriverLicenseContext(lines: [String], joined: String) -> Bool {
        let upper = joined.uppercased()
        if upper.contains("TEXAS") || upper.contains("TEXASS") { return true }
        if upper.contains("DRIVER LICENSE") && upper.contains("4D") { return true }
        return lines.contains { $0.range(of: #"(?i)4d\.?\s*DL"#, options: .regularExpression) != nil }
    }

    private static func captureTexasNumberedField(_ line: String, number: String) -> String? {
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

    private static func isTexasDOBLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        if lower.contains("dob") || lower.contains("bdate") { return true }
        return line.range(of: #"(?i)^[34zз]\.?\s"#, options: .regularExpression) != nil
            && line.range(of: #"\d{2}[/\-]\d"#, options: .regularExpression) != nil
    }

    private static func stripNameNoise(_ line: String) -> String {
        line
            .replacingOccurrences(of: #"^\d+\.?\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^[^\p{L}]+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isNameToken(_ token: String) -> Bool {
        guard !token.isEmpty, !isBoilerplateName(token) else { return false }
        guard token.range(of: #"^[A-Za-z][A-Za-z\-']*$"#, options: .regularExpression) != nil else { return false }
        return ScanFieldValidator.isPlausibleNameComponent(token)
    }

    private static func isPlausibleNameLine(_ line: String) -> Bool {
        let words = line.split(whereSeparator: \.isWhitespace)
        return words.count >= 2 && !isBoilerplateName(line)
    }

    private static func isBoilerplateName(_ value: String) -> Bool {
        let lower = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return [
            "driver", "license", "texas", "texass", "director", "limited", "term", "none", "eno",
            "class", "rest", "hgt", "sex", "eyes", "blk",
        ].contains(lower)
    }

    private static func lineLooksLikeAddress(_ line: String) -> Bool {
        line.range(of: #"^\d+\s+\S+"#, options: .regularExpression) != nil
            || line.range(of: #"(?i)^8\.?\s"#, options: .regularExpression) != nil
    }

    private static func captureGroup(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let r = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Overlay authoritative passport fields without dropping other extracted keys (e.g. GenAI).
    private static func mergePassportSuggestions(
        _ passport: [OcrFieldSuggestion],
        into suggestions: [OcrFieldSuggestion]
    ) -> [OcrFieldSuggestion] {
        var byKey = Dictionary(uniqueKeysWithValues: suggestions.map { ($0.profileKey, $0) })
        for item in passport {
            byKey[item.profileKey] = item
        }
        return ProfileSchema.sortSuggestions(Array(byKey.values))
    }
}
