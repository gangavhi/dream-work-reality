import Foundation

/// Local ML extraction for **any** document. Template extraction, machine-readable boosters, and
/// learned replay are intentionally excluded from the scan pipeline.
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
        strategy: ExtractionStrategyAgent.Result
    ) async -> Result {
        _ = payloadHints
        _ = templateMatch
        _ = strategy

        var suggestions: [OcrFieldSuggestion] = []
        var usedSemanticExtractor = false
        var usedAI = false
        var openType = classification.openDocumentType
        let usedHeuristicFallback = false
        var runtimeStatus: String?

        switch GenAISettings.provider {
        case .onDevice:
            if let mapped = OnDeviceFieldMapper.mapFields(
                layoutText: layout.modelInput,
                profileSchemaKeys: schemaKeys
            ) {
                suggestions = mapped.suggestions
                openType = openType ?? mapped.documentType
                usedAI = usedAI || !mapped.suggestions.isEmpty
                if !mapped.suggestions.isEmpty { usedSemanticExtractor = true }
                runtimeStatus = "\(mapped.engine):\(mapped.modelArtifactID):gguf_present=\(mapped.ggufPresent):gguf_valid=\(mapped.ggufValid):\(mapped.llmRuntimeStatus)"
            } else {
                runtimeStatus = "llm_document_parser_failed:bridge_or_input_empty"
            }
        case .off:
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
