import Foundation

/// On-device document type detection without cloud APIs.
/// Combines machine-readable signals, keyword heuristics, and optional local GGUF classifier.
enum LocalDocumentClassifier {
    static func classify(
        layoutText: String,
        modelInput: String,
        payloadHints: EmbeddedPayloadHints.Result,
        allowHeavyLLM: Bool
    ) -> ClassificationAgent.Result {
        if !payloadHints.mrzLines.isEmpty {
            return activeResult(
                openType: "passport",
                confidence: 0.98,
                status: "classifier_active:mrz",
                engineID: "mrz"
            )
        }

        if !payloadHints.barcodePayloads.isEmpty {
            let openType = inferBarcodeDocumentType(payloadHints.barcodePayloads, layoutText: layoutText)
            return activeResult(
                openType: openType,
                confidence: 0.94,
                status: "classifier_active:barcode",
                engineID: "pdf417"
            )
        }

        let corpus = layoutText + "\n" + modelInput
        let keywordType = ProfileSchemaKeysForDocument.inferOpenType(from: corpus)
        if keywordType != "other" {
            return activeResult(
                openType: keywordType,
                confidence: 0.78,
                status: "classifier_active:keyword",
                engineID: "keyword"
            )
        }

        if allowHeavyLLM,
           OnDeviceMemoryGuard.mayRunHeavyInference(),
           GenAISettings.provider == .onDevice
        {
            let gguf = ClassificationAgent.classify(
                modelInput: modelInput,
                mappedDocumentType: nil,
                machineReadableSources: []
            )
            if gguf.runtimeStatus == "classifier_active" {
                return gguf
            }
        }

        return ClassificationAgent.pendingParserClassification()
    }

    private static func inferBarcodeDocumentType(_ payloads: [String], layoutText: String) -> String {
        let joined = payloads.joined(separator: "\n").uppercased()
        let layout = layoutText.uppercased()
        if joined.contains("ANSI ") || layout.contains("DRIVER") || layout.contains("DL ") {
            return "drivers_license"
        }
        if joined.contains("INSURANCE") || layout.contains("MEMBER ID") || layout.contains("GROUP #") {
            return "insurance_card"
        }
        return "drivers_license"
    }

    private static func activeResult(
        openType: String,
        confidence: Double,
        status: String,
        engineID: String
    ) -> ClassificationAgent.Result {
        let presentation = DocumentTypePresentation.resolve(openType)
        return ClassificationAgent.Result(
            openDocumentType: openType,
            displayLabel: presentation.displayLabel,
            enumType: presentation.enumType,
            confidence: confidence,
            engineID: engineID,
            issuerRegion: nil,
            country: nil,
            runtimeStatus: status
        )
    }
}
