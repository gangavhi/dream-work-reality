import Foundation
import NaturalLanguage

/// Optional Create ML text classifier (`trustnest.doc-type.v1`) — hint-only, heuristic fallback.
enum StandaloneDocumentTypeClassifier {
    private static let confidenceThreshold = 0.75
    private static let heuristicBypassThreshold = 0.85

    /// When heuristic confidence is below bypass threshold, try bundled Create ML classifier.
    static func classifyIfNeeded(
        ocrText: String,
        heuristic: DocumentClassification
    ) -> DocumentClassification? {
        guard heuristic.confidence < heuristicBypassThreshold else { return nil }
        guard let result = classify(ocrText: ocrText) else { return nil }
        guard result.confidence >= confidenceThreshold else { return nil }
        return result
    }

    static func classify(ocrText: String) -> DocumentClassification? {
        guard let model = CreateMLModelRegistry.documentTypeClassifier else { return nil }
        let sample = String(ocrText.prefix(4000)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sample.isEmpty,
              let rawLabel = model.predictedLabel(for: sample)
        else { return nil }

        let presentation = DocumentTypePresentation.resolve(rawLabel)
        guard presentation.enumType != .other else { return nil }

        return DocumentClassification(
            documentType: presentation.enumType,
            confidence: 0.88,
            matchedSignals: ["createml:\(rawLabel)"]
        )
    }
}
