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

    /// Pairs a short left block with a right block on the same row — no document-specific field numbers.
    static func labelValuePairs(from blocks: [LayoutBlock], maxPairs: Int = 24) -> [LabelValuePair] {
        var pairs: [LabelValuePair] = []
        let rowTolerance: Float = 0.03

        for i in 0 ..< blocks.count {
            guard pairs.count < maxPairs else { break }
            let left = blocks[i]
            guard left.text.count <= 48 else { continue }

            for j in (i + 1) ..< blocks.count {
                let right = blocks[j]
                guard abs(left.y - right.y) <= rowTolerance else {
                    if right.y < left.y - rowTolerance { break }
                    continue
                }
                guard right.x > left.x + 0.05 else { continue }
                guard right.text.count >= 2, right.text.count <= 80 else { continue }
                guard looksLikeLabel(left.text), !looksLikeLabel(right.text) else { continue }

                pairs.append(LabelValuePair(label: left.text, value: right.text))
                break
            }
        }
        return pairs
    }

    private static func looksLikeLabel(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 40 else { return false }
        if trimmed.hasSuffix(":") { return true }
        if trimmed == trimmed.uppercased(), trimmed.rangeOfCharacter(from: .letters) != nil {
            return true
        }
        return trimmed.count <= 24 && trimmed.contains(where: { $0.isLetter })
    }
}
