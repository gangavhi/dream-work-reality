import Foundation

/// On-device document type detection: MRZ, barcode, keywords, optional Create ML.
enum LocalDocumentClassifier {
    static func classify(
        layoutText: String,
        modelInput: String,
        payloadHints: EmbeddedPayloadHints.Result,
        allowHeavyLLM: Bool
    ) -> ClassificationAgent.Result {
        _ = allowHeavyLLM
        let nl = NLDocumentClassifier.classify(layoutText: layoutText + "\n" + modelInput, payloadHints: payloadHints)
        let presentation = DocumentTypePresentation.resolve(nl.openLabel)
        return ClassificationAgent.Result(
            openDocumentType: nl.openLabel,
            displayLabel: presentation.displayLabel,
            enumType: presentation.enumType,
            confidence: nl.confidence,
            engineID: nl.engineID,
            issuerRegion: nil,
            country: nil,
            runtimeStatus: "classifier_active:\(nl.engineID)"
        )
    }
}
