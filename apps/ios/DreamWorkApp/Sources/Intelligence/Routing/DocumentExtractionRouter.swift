import Foundation

/// Routes documents to fast specialized extraction vs heavy semantic extraction.
/// Avoids running all models on every scan (latency, memory, battery).
enum DocumentExtractionRouter {
    enum Route: String, Hashable {
        /// MRZ, PDF417, known type + layout priors, ONNX label mapping.
        case knownFastPath = "known_fast"
        /// Unstructured / unknown — local LLM, layout-AI chunks, regex, optional VLM when installed.
        case unknownSemantic = "unknown_semantic"
    }

    struct Decision: Hashable {
        let route: Route
        let signals: [String]
        let openDocumentType: String?
    }

    static func decide(
        classification: ClassificationAgent.Result,
        payloadHints: EmbeddedPayloadHints.Result,
        layout: LayoutIntelligenceAgent.LayoutDocument
    ) -> Decision {
        var signals: [String] = []
        let openType = classification.openDocumentType

        if KnownDocumentRegistry.hasMachineReadableSignal(payloadHints) {
            if !payloadHints.mrzLines.isEmpty { signals.append("signal:mrz") }
            if !payloadHints.barcodePayloads.isEmpty { signals.append("signal:pdf417") }
            return Decision(route: .knownFastPath, signals: signals, openDocumentType: openType ?? inferredType(from: payloadHints))
        }

        if let openType, KnownDocumentRegistry.isKnown(openType: openType) {
            signals.append("signal:known_type:\(openType)")
            if KnownDocumentRegistry.hasStructuredLayout(layout) {
                signals.append("signal:layout_pairs:\(layout.labelValuePairs.count)")
            }
            if classification.confidence >= 0.65 {
                signals.append("signal:classifier_conf:\(String(format: "%.2f", classification.confidence))")
            }
            return Decision(route: .knownFastPath, signals: signals, openDocumentType: openType)
        }

        let keywordType = ProfileSchemaKeysForDocument.inferOpenType(from: layout.layoutText + "\n" + layout.modelInput)
        if keywordType != "other", KnownDocumentRegistry.isKnown(openType: keywordType) {
            signals.append("signal:keyword_type:\(keywordType)")
            if KnownDocumentRegistry.hasStructuredLayout(layout) {
                signals.append("signal:layout_pairs:\(layout.labelValuePairs.count)")
            }
            return Decision(route: .knownFastPath, signals: signals, openDocumentType: keywordType)
        }

        if KnownDocumentRegistry.hasStructuredLayout(layout), classification.confidence >= 0.72 {
            signals.append("signal:semi_structured_layout")
            signals.append("signal:classified:\(openType ?? "unknown")")
            return Decision(route: .knownFastPath, signals: signals, openDocumentType: openType)
        }

        signals.append("signal:unknown_or_unstructured")
        if layout.labelValuePairs.isEmpty {
            signals.append("signal:no_label_pairs")
        }
        return Decision(
            route: .unknownSemantic,
            signals: signals,
            openDocumentType: openType ?? (keywordType == "other" ? nil : keywordType)
        )
    }

    private static func inferredType(from hints: EmbeddedPayloadHints.Result) -> String? {
        if !hints.mrzLines.isEmpty { return "passport" }
        if !hints.barcodePayloads.isEmpty { return "drivers_license" }
        return nil
    }
}
