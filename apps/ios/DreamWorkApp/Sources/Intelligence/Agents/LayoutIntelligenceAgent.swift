import Foundation

/// Layout intelligence — model-only label/value pairing. Heuristic spatial pairing is intentionally disabled.
enum LayoutIntelligenceAgent {
    struct LayoutDocument: Hashable {
        let layoutText: String
        let modelInput: String
        let blocks: [OcrLayoutSerializer.LayoutBlock]
        let labelValuePairs: [OcrLayoutSerializer.LabelValuePair]
        let engineID: String
    }

    static func analyze(
        document: VisionOcrAdapter.NormalizedDocument,
        payloadHints: EmbeddedPayloadHints.Result
    ) -> LayoutDocument {
        let layoutText = OcrLayoutSerializer.serialize(document: document)
        let blocks = document.pages.flatMap(\.blocks).map { block in
            OcrLayoutSerializer.LayoutBlock(
                text: block.text,
                confidence: block.confidence,
                x: block.bounds.x,
                y: block.bounds.y,
                width: block.bounds.width,
                height: block.bounds.height
            )
        }
        let modelState = ModelArtifactRegistry.loadState(for: .layoutLM)
        let inference: LayoutLMv3CoreMLAdapter.Result? = {
            switch modelState {
            case .installed(let path):
                return LayoutLMv3CoreMLAdapter.inferPairs(blocks: blocks, modelPath: path)
            default:
                return nil
            }
        }()
        let pairs: [OcrLayoutSerializer.LabelValuePair] = {
            if let inference, !inference.pairs.isEmpty {
                return inference.pairs
            }
            return OcrLayoutSerializer.labelValuePairs(from: blocks)
        }()
        let engineID: String = {
            switch modelState {
            case .installed:
                if let inference, !inference.pairs.isEmpty {
                    return inference.status ?? ModelArtifactSlot.layoutLM.rawValue
                }
                return "layout.heuristic_pairs:\(pairs.count)"
            default:
                return pairs.isEmpty ? "layout.heuristic_pairs:0" : "layout.heuristic_pairs:\(pairs.count)"
            }
        }()

        return LayoutDocument(
            layoutText: layoutText,
            modelInput: OcrLayoutSerializer.modelInput(document: document, payloadHints: payloadHints),
            blocks: blocks,
            labelValuePairs: pairs,
            engineID: engineID
        )
    }

    /// Model-produced LayoutLM pairs can be mapped through semantic label keys first.
    static func suggestionsFromLayoutPairs(_ pairs: [OcrLayoutSerializer.LabelValuePair]) -> [OcrFieldSuggestion] {
        let stub = LayoutDocument(
            layoutText: pairs.map { "\($0.label) | \($0.value)" }.joined(separator: "\n"),
            modelInput: "",
            blocks: [],
            labelValuePairs: pairs,
            engineID: ModelArtifactSlot.layoutLM.rawValue
        )
        return OpenVocabularyFieldExtractor.suggestions(from: stub)
    }
}
