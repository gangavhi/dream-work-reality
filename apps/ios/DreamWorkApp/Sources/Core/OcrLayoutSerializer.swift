import Foundation

/// Turns normalized OCR blocks into reading-order text for on-device LLM ingest (no per-format templates).
enum OcrLayoutSerializer {
    struct LayoutBlock: Hashable {
        let text: String
        let confidence: Float
        let x: Float
        let y: Float
        let width: Float
        let height: Float
    }

    /// Blocks in top-to-bottom, left-to-right order (Vision adapter uses top-left origin in `NormRect.y`).
    static func orderedBlocks(from document: VisionOcrAdapter.NormalizedDocument) -> [LayoutBlock] {
        document.pages
            .flatMap(\.blocks)
            .compactMap { block -> LayoutBlock? in
                let text = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                return LayoutBlock(
                    text: text,
                    confidence: block.confidence,
                    x: block.bounds.x,
                    y: block.bounds.y,
                    width: block.bounds.width,
                    height: block.bounds.height
                )
            }
            .sorted { lhs, rhs in
                if abs(lhs.y - rhs.y) > 0.02 {
                    return lhs.y > rhs.y
                }
                return lhs.x < rhs.x
            }
    }

    /// Plain text: one line per block in reading order.
    static func serialize(document: VisionOcrAdapter.NormalizedDocument) -> String {
        orderedBlocks(from: document)
            .map(\.text)
            .joined(separator: "\n")
    }

    /// Prompt body: layout lines plus optional generic label|value pairs from spatial neighbors.
    static func modelInput(
        document: VisionOcrAdapter.NormalizedDocument,
        payloadHints: EmbeddedPayloadHints.Result = .empty
    ) -> String {
        let blocks = orderedBlocks(from: document)
        var sections: [String] = []

        sections.append("## OCR blocks (top-to-bottom, left-to-right)")
        if blocks.isEmpty {
            sections.append("(no text blocks)")
        } else {
            for (index, block) in blocks.enumerated() {
                sections.append("[\(index + 1)] \(block.text)")
            }
            let pairs = labelValuePairs(from: blocks)
            if !pairs.isEmpty {
                sections.append("")
                sections.append("## Spatial label | value pairs (heuristic)")
                for pair in pairs {
                    sections.append("\(pair.label) | \(pair.value)")
                }
            }
        }

        if let appendix = payloadHints.promptAppendix, !appendix.isEmpty {
            sections.append("")
            sections.append(appendix)
        }

        return sections.joined(separator: "\n")
    }

    struct LabelValuePair: Hashable {
        let label: String
        let value: String
    }

    /// Pairs spatial neighbors: same-row (label left, value right) and stacked (label above value).
    static func labelValuePairs(from blocks: [LayoutBlock], maxPairs: Int = 32) -> [LabelValuePair] {
        var pairs: [LabelValuePair] = []
        let rowTolerance: Float = 0.03
        let colTolerance: Float = 0.2
        let verticalGapMin: Float = 0.008
        let verticalGapMax: Float = 0.14

        for i in 0 ..< blocks.count {
            guard pairs.count < maxPairs else { break }
            let left = blocks[i]

            if let inline = inlineLabelValue(from: left.text) {
                pairs.append(inline)
                continue
            }

            guard isFieldLabel(left.text) else { continue }

            for j in (i + 1) ..< blocks.count {
                let right = blocks[j]
                guard abs(left.y - right.y) <= rowTolerance else {
                    if right.y < left.y - rowTolerance { break }
                    continue
                }
                guard right.x > left.x + 0.05 else { continue }
                guard looksLikeFieldValue(right.text, forLabel: left.text) else { continue }

                pairs.append(LabelValuePair(label: left.text, value: right.text))
                break
            }
        }

        for i in 0 ..< blocks.count {
            guard pairs.count < maxPairs else { break }
            let labelBlock = blocks[i]
            guard isFieldLabel(labelBlock.text), !labelBlock.text.contains("|") else { continue }

            for j in 0 ..< blocks.count where i != j {
                let valueBlock = blocks[j]
                let verticalGap = labelBlock.y - valueBlock.y
                guard verticalGap > verticalGapMin, verticalGap < verticalGapMax else { continue }
                guard abs(labelBlock.x - valueBlock.x) <= colTolerance else { continue }
                guard looksLikeFieldValue(valueBlock.text, forLabel: labelBlock.text) else { continue }

                pairs.append(LabelValuePair(label: labelBlock.text, value: valueBlock.text))
                break
            }
        }

        return dedupePairs(pairs).prefix(maxPairs).map { $0 }
    }

    private static func dedupePairs(_ pairs: [LabelValuePair]) -> [LabelValuePair] {
        var seen = Set<String>()
        return pairs.filter { pair in
            let key = "\(normalizeLabel(pair.label))|\(pair.value.lowercased())"
            return seen.insert(key).inserted
        }
    }

    /// Single-block labels like `Date of Birth 15/03/1985` or `Passport No. M1234567`.
    static func inlineLabelValue(from text: String) -> LabelValuePair? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.contains("|") { return nil }

        if let colon = trimmed.firstIndex(of: ":") {
            let label = String(trimmed[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(trimmed[trimmed.index(after: colon)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if isFieldLabel(label), looksLikeFieldValue(value, forLabel: label) {
                return LabelValuePair(label: label, value: value)
            }
        }

        let patterns: [(String, Int, Int)] = [
            (#"(?i)^(date of birth)\s+(.+)$"#, 1, 2),
            (#"(?i)^(date of issue)\s+(.+)$"#, 1, 2),
            (#"(?i)^(date of expir(?:y|ation))\s+(.+)$"#, 1, 2),
            (#"(?i)^(place of birth)\s+(.+)$"#, 1, 2),
            (#"(?i)^(place of issue)\s+(.+)$"#, 1, 2),
            (#"(?i)^(passport\s*(?:no|number|#)?\.?)\s*([A-Z0-9]{6,12})$"#, 1, 2),
            (#"(?i)^(surname|given names?)\s+(.+)$"#, 1, 2),
            (#"(?i)^(nationality)\s+(.+)$"#, 1, 2),
            (#"(?i)^(sex|gender)\s+(.+)$"#, 1, 2),
        ]
        for (pattern, labelGroup, valueGroup) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
                  match.numberOfRanges > valueGroup,
                  let labelRange = Range(match.range(at: labelGroup), in: trimmed),
                  let valueRange = Range(match.range(at: valueGroup), in: trimmed)
            else { continue }
            let label = String(trimmed[labelRange])
            let value = String(trimmed[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            if looksLikeFieldValue(value, forLabel: label) {
                return LabelValuePair(label: label, value: value)
            }
        }
        return nil
    }

    private static func matchesKnownLabelPhrase(_ text: String) -> Bool {
        let normalized = normalizeLabel(text)
        return knownFieldLabelPhrases.contains(where: { phrase in
            normalized == phrase || normalized.hasPrefix(phrase + " ") || normalized.hasSuffix(" " + phrase)
        })
    }

    private static func isFieldLabel(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 48 else { return false }
        if trimmed.contains("|") { return false }
        if containsObviousValuePattern(trimmed) { return false }

        if matchesKnownLabelPhrase(trimmed) {
            return true
        }
        if trimmed.hasSuffix(":") { return true }
        if trimmed == trimmed.uppercased(), trimmed.rangeOfCharacter(from: .letters) != nil, trimmed.count <= 32 {
            return true
        }
        let words = trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        if words.count == 1, trimmed.count <= 24, trimmed.contains(where: { $0.isLetter }) {
            return true
        }
        if words.count <= 4, trimmed == trimmed.uppercased(), trimmed.contains(where: { $0.isLetter }) {
            return true
        }
        return false
    }

    private static func looksLikeFieldValue(_ text: String, forLabel: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 1, trimmed.count <= 80 else { return false }

        let labelNorm = normalizeLabel(forLabel)
        if labelNorm.isEmpty {
            if isFieldLabel(trimmed) { return false }
        } else if matchesKnownLabelPhrase(trimmed), labelNorm != normalizeLabel(trimmed) {
            return false
        }

        if labelNorm.isEmpty {
            if trimmed == trimmed.uppercased(), trimmed.count > 24 { return false }
            return true
        }

        if labelNorm.contains("date") || labelNorm.contains("dob") || labelNorm.contains("birth") {
            return trimmed.range(of: #"\d"#, options: .regularExpression) != nil
        }
        if labelNorm.contains("passport") && (labelNorm.contains("no") || labelNorm.contains("number")) {
            return trimmed.range(of: #"^[A-Z0-9]{6,12}$"#, options: .regularExpression) != nil
        }
        if labelNorm.contains("surname") || labelNorm.contains("given") || labelNorm.contains("name") {
            return trimmed.range(of: #"^[A-Za-z][A-Za-z\s\-'.]{1,}$"#, options: .regularExpression) != nil
        }
        if labelNorm.contains("nationality") || labelNorm.contains("sex") || labelNorm.contains("gender") {
            return trimmed.count >= 2 && trimmed.count <= 32
        }
        if labelNorm.contains("place") {
            return trimmed.count >= 2
        }

        // Generic value: not a section header (all caps long line).
        if trimmed == trimmed.uppercased(), trimmed.count > 24 { return false }
        return true
    }

    private static func containsObviousValuePattern(_ text: String) -> Bool {
        if text.range(of: #"\d{1,2}/\d{1,2}/\d{2,4}"#, options: .regularExpression) != nil { return true }
        if text.range(of: #"^[A-Z]\d{6,9}$"#, options: .regularExpression) != nil { return true }
        if text.contains("@") { return true }
        if text.range(of: #"^\d{4,}$"#, options: .regularExpression) != nil { return true }
        return false
    }

    private static func normalizeLabel(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "(s)", with: "")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let knownFieldLabelPhrases: [String] = [
        "surname", "given name", "given names", "first name", "last name", "middle name",
        "full name", "display name", "name", "dob", "date of birth", "birth date",
        "date of issue", "date of expiry", "date of expiration", "expiry", "expiration",
        "passport no", "passport number", "nationality", "sex", "gender",
        "place of birth", "place of issue", "address", "city", "state", "zip", "postal",
        "license no", "license number", "dl no", "member id", "policy number", "ssn",
        "email", "phone", "mobile", "employer", "country",
    ]

    private static func looksLikeLabel(_ text: String) -> Bool {
        isFieldLabel(text)
    }
}
