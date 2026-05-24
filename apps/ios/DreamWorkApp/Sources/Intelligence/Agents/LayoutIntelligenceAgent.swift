import Foundation

/// Layout intelligence — heuristic blocks today; LayoutLMv3 CoreML slot when bundled.
enum LayoutIntelligenceAgent {
    struct LayoutDocument: Hashable {
        let layoutText: String
        let modelInput: String
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
        let pairs = OcrLayoutSerializer.labelValuePairs(from: blocks)
        let engineID: String = {
            switch ModelArtifactRegistry.loadState(for: .layoutLM) {
            case .installed: return ModelArtifactSlot.layoutLM.rawValue
            default: return "layout.heuristic.v1"
            }
        }()

        return LayoutDocument(
            layoutText: layoutText,
            modelInput: OcrLayoutSerializer.modelInput(document: document, payloadHints: payloadHints),
            labelValuePairs: pairs,
            engineID: engineID
        )
    }

    /// When LayoutLM ships, map pairs through semantic label keys first.
    static func suggestionsFromLayoutPairs(_ pairs: [OcrLayoutSerializer.LabelValuePair]) -> [OcrFieldSuggestion] {
        let stub = LayoutDocument(
            layoutText: pairs.map { "\($0.label) | \($0.value)" }.joined(separator: "\n"),
            modelInput: "",
            labelValuePairs: pairs,
            engineID: "layout.heuristic.v1"
        )
        return OpenVocabularyFieldExtractor.suggestions(from: stub)
    }
}
