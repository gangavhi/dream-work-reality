import Foundation

/// Local ML extraction for **any** document. ONNX label mapping runs first; GGUF is optional/heavy.
enum ExtractionAgent {
    struct Result: Hashable {
        var suggestions: [OcrFieldSuggestion]
        var openDocumentType: String?
        var usedAI: Bool
        var usedHeuristicFallback: Bool
        var usedTemplateExtractor: Bool
        var usedSemanticExtractor: Bool
        var learnedSuggestionCount: Int
        var onDeviceRuntimeStatus: String?
    }

    static func extract(
        layout: LayoutIntelligenceAgent.LayoutDocument,
        payloadHints: EmbeddedPayloadHints.Result,
        schemaKeys: [String],
        classification: ClassificationAgent.Result,
        templateMatch: DocumentTemplateAgent.Match?,
        strategy: ExtractionStrategyAgent.Result,
        allowHeavyLLM: Bool = true
    ) async -> Result {
        _ = payloadHints
        _ = templateMatch
        _ = strategy
        _ = schemaKeys

        var suggestions: [OcrFieldSuggestion] = []
        var usedSemanticExtractor = false
        var usedAI = false
        var openType = classification.openDocumentType
        let usedHeuristicFallback = false
        var runtimeStatus: String?

        if GenAISettings.provider == .onDevice {
            let onnxSuggestions = OpenVocabularyFieldExtractor.suggestions(
                from: layout,
                documentTypeHint: classification.openDocumentType
            )
            if !onnxSuggestions.isEmpty {
                suggestions = onnxSuggestions
                usedSemanticExtractor = true
                usedAI = MiniLMOnnxFieldEmbedder.shared.isAvailable
                runtimeStatus = OnnxFieldLabelMapper.runtimeStatus()
            } else if MiniLMOnnxFieldEmbedder.shared.isAvailable {
                runtimeStatus = "\(OnnxFieldLabelMapper.runtimeStatus()):no_pairs_mapped"
            }

            if suggestions.isEmpty, allowHeavyLLM, OnDeviceMemoryGuard.mayRunHeavyInference() {
                if let mapped = OnDeviceFieldMapper.mapFields(
                    layoutText: layout.modelInput,
                    profileSchemaKeys: schemaKeys
                ) {
                    suggestions = mapped.suggestions
                    openType = openType ?? mapped.documentType
                    usedAI = usedAI || !mapped.suggestions.isEmpty
                    if !mapped.suggestions.isEmpty { usedSemanticExtractor = true }
                    runtimeStatus = "\(mapped.engine):\(mapped.modelArtifactID):gguf_present=\(mapped.ggufPresent):gguf_valid=\(mapped.ggufValid):\(mapped.llmRuntimeStatus)"
                } else if runtimeStatus == nil {
                    runtimeStatus = "llm_document_parser_failed:bridge_or_input_empty"
                }
            } else if suggestions.isEmpty, !allowHeavyLLM, runtimeStatus == nil {
                runtimeStatus = "llm:heavy:deferred:\(OnDeviceMemoryGuard.skipTraceToken)"
            } else if suggestions.isEmpty, runtimeStatus == nil {
                runtimeStatus = "onnx_field_mapper:no_suggestions:\(OnDeviceMemoryGuard.skipTraceToken)"
            }
        } else {
            runtimeStatus = "llm_document_parser_failed:provider_off"
        }

        return Result(
            suggestions: suggestions,
            openDocumentType: openType,
            usedAI: usedAI,
            usedHeuristicFallback: usedHeuristicFallback,
            usedTemplateExtractor: false,
            usedSemanticExtractor: usedSemanticExtractor,
            learnedSuggestionCount: 0,
            onDeviceRuntimeStatus: runtimeStatus
        )
    }
}
