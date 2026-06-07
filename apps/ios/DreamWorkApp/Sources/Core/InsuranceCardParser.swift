import Foundation

/// Health insurance card OCR — UHC portal exports, carrier logos, and standard member/group labels.
enum InsuranceCardParser {
    private struct CarrierHint {
        let displayName: String
        let needles: [String]
    }

    private static let carriers: [CarrierHint] = [
        CarrierHint(displayName: "UnitedHealthcare", needles: [
            "UNITEDHEALTHCARE", "UNITED HEALTHCARE", "UNITED HEALTH", "UHC", "UHCMEDICARE",
        ]),
        CarrierHint(displayName: "Aetna", needles: ["AETNA"]),
        CarrierHint(displayName: "Anthem", needles: ["ANTHEM"]),
        CarrierHint(displayName: "Cigna", needles: ["CIGNA"]),
        CarrierHint(displayName: "Humana", needles: ["HUMANA"]),
        CarrierHint(displayName: "Blue Cross Blue Shield", needles: [
            "BLUE CROSS", "BLUE SHIELD", "BCBS",
        ]),
        CarrierHint(displayName: "Kaiser Permanente", needles: ["KAISER"]),
    ]

    static func isInsuranceCard(_ text: String) -> Bool {
        let upper = text.uppercased()
        guard !upper.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }

        if upper.contains("DRIVER") && upper.contains("LICENSE") { return false }
        if UniversalDocumentParser.looksLikeSSNDocument(text) { return false }

        var signals = 0
        if upper.contains("MEMBER") || upper.contains("SUBSCRIBER") { signals += 1 }
        if upper.contains("RXBIN") || upper.contains("RX BIN") { signals += 1 }
        if upper.range(of: #"(?i)GROUP\s*#?"#, options: .regularExpression) != nil { signals += 1 }
        if upper.contains("ID CARDS AS OF") || upper.contains("ID CARD") { signals += 1 }
        if upper.contains("MEDICAL") && (upper.contains("FRONT") || upper.contains("BACK")) { signals += 1 }
        if inferCarrier(from: upper) != nil { signals += 1 }
        if upper.range(of: #"(?i)DOB\s*:\s*\d{1,2}/\d{1,2}/\d{4}"#, options: .regularExpression) != nil,
           upper.contains("ID CARDS")
        {
            signals += 1
        }

        return signals >= 2
    }

    static func suggestions(from text: String) -> [OcrFieldSuggestion] {
        guard isInsuranceCard(text) else { return [] }

        let lines = text
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var out: [OcrFieldSuggestion] = []
        func add(_ key: String, _ value: String?, _ score: Double) {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmed.isEmpty else { return }
            out.append(
                OcrFieldSuggestion(
                    profileKey: key,
                    label: ProfileSchema.definition(for: key)?.label ?? key,
                    value: trimmed,
                    confidence: score >= 0.85 ? "High" : "Medium",
                    confidenceScore: score
                )
            )
        }

        if let carrier = inferCarrier(from: text.uppercased()) {
            add(ProfileFieldKey.insuranceCarrier, carrier, 0.9)
        }

        if let memberId = extractMemberId(from: text, lines: lines) {
            add(ProfileFieldKey.insuranceMemberId, memberId, 0.88)
        }

        if let portal = extractPortalHolder(from: lines) {
            if let display = portal.displayName, ScanFieldValidator.isPlausiblePersonName(display) {
                add(ProfileFieldKey.displayName, display, 0.86)
            }
            if let first = portal.first, ScanFieldValidator.isPlausibleNameComponent(first) {
                add(ProfileFieldKey.legalFirstName, first, 0.86)
            }
            if let last = portal.last, ScanFieldValidator.isPlausibleNameComponent(last) {
                add(ProfileFieldKey.legalLastName, last, 0.86)
            }
            if let dob = portal.dob {
                add(ProfileFieldKey.dateOfBirth, dob, 0.84)
            }
        }

        var seen = Set<String>()
        return out.filter { seen.insert($0.profileKey).inserted }
    }

    // MARK: - Carrier

    private static func inferCarrier(from upper: String) -> String? {
        let normalized = upper
            .replacingOccurrences(of: #"[^A-Z0-9\s]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)

        for carrier in carriers {
            for needle in carrier.needles where normalized.contains(needle) {
                return carrier.displayName
            }
        }

        let reversed = String(normalized.reversed())
        for carrier in carriers {
            for needle in carrier.needles where reversed.contains(needle) {
                return carrier.displayName
            }
        }
        return nil
    }

    // MARK: - Member ID

    private static func extractMemberId(from text: String, lines: [String]) -> String? {
        let labeledPatterns = [
            #"(?i)(?:MEMBER|SUBSCRIBER|ID)\s*(?:ID|#|NO\.?)?\s*:?\s*([A-Z0-9]{8,14})"#,
            #"(?i)(?:MEMBER|SUBSCRIBER)\s*#\s*([A-Z0-9]{8,14})"#,
        ]
        for pattern in labeledPatterns {
            if let raw = firstCapture(in: text, pattern: pattern), isPlausibleMemberId(raw) {
                return normalizeMemberId(raw)
            }
        }

        var counts: [String: Int] = [:]
        let tokenPattern = #"\b([A-Z0-9]{8,14})\b"#
        guard let regex = try? NSRegularExpression(pattern: tokenPattern) else { return nil }
        let joined = lines.joined(separator: "\n")
        let range = NSRange(joined.startIndex..., in: joined)
        regex.enumerateMatches(in: joined, range: range) { match, _, _ in
            guard let match, match.numberOfRanges > 1,
                  let r = Range(match.range(at: 1), in: joined)
            else { return }
            let token = normalizeMemberId(String(joined[r]))
            guard isPlausibleMemberId(token) else { return }
            counts[token, default: 0] += 1
        }

        return counts.max(by: { $0.value < $1.value })?.key
    }

    private static func normalizeMemberId(_ raw: String) -> String {
        raw
            .uppercased()
            .replacingOccurrences(of: "O", with: "0")
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func isPlausibleMemberId(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard (8 ... 14).contains(trimmed.count) else { return false }
        let digits = trimmed.filter(\.isNumber).count
        guard digits >= 6 else { return false }
        guard Double(digits) / Double(trimmed.count) >= 0.5 else { return false }

        let banned = ["MEDICAL", "FRONT", "BACK", "SOZO", "MEMBER", "UNITED"]
        if banned.contains(where: { trimmed.contains($0) }) { return false }
        if Set(trimmed).count <= 2 { return false }
        return true
    }

    // MARK: - UHC portal export header

    private struct PortalHolder {
        var first: String?
        var last: String?
        var displayName: String?
        var dob: String?
    }

    private static func extractPortalHolder(from lines: [String]) -> PortalHolder? {
        guard let headerIdx = lines.firstIndex(where: {
            $0.range(of: #"(?i)'s\s+ID\s+Cards"#, options: .regularExpression) != nil
        }) else { return nil }

        let header = lines[headerIdx]
        guard let regex = try? NSRegularExpression(pattern: #"^(.+?)'s\s+ID\s+Cards"#, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: header, range: NSRange(header.startIndex..., in: header)),
              match.numberOfRanges > 1,
              let nameRange = Range(match.range(at: 1), in: header)
        else { return nil }

        let nameRaw = String(header[nameRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        var holder = PortalHolder()
        let parts = nameRaw.split(whereSeparator: \.isWhitespace).map(String.init)
        if parts.count >= 2 {
            holder.first = DriverLicenseFormatting.personName(parts[0])
            holder.last = DriverLicenseFormatting.personName(parts.last!)
            holder.displayName = DriverLicenseFormatting.displayName(first: holder.first, middle: nil, last: holder.last)
        } else if parts.count == 1 {
            holder.displayName = DriverLicenseFormatting.personName(parts[0])
        }

        for offset in 1 ... 3 where headerIdx + offset < lines.count {
            let line = lines[headerIdx + offset]
            if let dob = firstCapture(in: line, pattern: #"(?i)DOB\s*:\s*(\d{1,2}/\d{1,2}/\d{4})"#) {
                holder.dob = dob
                break
            }
        }

        return holder
    }

    // MARK: - Helpers

    private static func firstCapture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let r = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
