import Foundation

/// Local ML extraction — routes known documents to fast parsers, unknown to semantic models.
enum ExtractionAgent {
    struct Result: Hashable {
        var suggestions: [OcrFieldSuggestion]
        var openDocumentType: String?
        var usedAI: Bool
        var usedHeuristicFallback: Bool
        var usedTemplateExtractor: Bool
        var usedSemanticExtractor: Bool
        var usedMachineReadablePayload: Bool
        var learnedSuggestionCount: Int
        var onDeviceRuntimeStatus: String?
        var extractionRoute: DocumentExtractionRouter.Route
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
        _ = templateMatch

        let resolvedSchemaKeys = schemaKeys.isEmpty
            ? ProfileSchema.allFields.map(\.key)
            : schemaKeys

        guard GenAISettings.provider == .onDevice else {
            return emptyResult(route: strategy.route, runtimeStatus: "llm_document_parser_failed:provider_off")
        }

        switch strategy.route {
        case .knownFastPath:
            return extractKnownFastPath(
                layout: layout,
                payloadHints: payloadHints,
                classification: classification,
                schemaKeys: resolvedSchemaKeys,
                allowHeavyLLM: allowHeavyLLM,
                route: strategy.route
            )
        case .unknownSemantic:
            return extractUnknownSemanticPath(
                layout: layout,
                payloadHints: payloadHints,
                classification: classification,
                schemaKeys: resolvedSchemaKeys,
                allowHeavyLLM: allowHeavyLLM,
                route: strategy.route
            )
        }
    }

    // MARK: - Known fast path

    private static func extractKnownFastPath(
        layout: LayoutIntelligenceAgent.LayoutDocument,
        payloadHints: EmbeddedPayloadHints.Result,
        classification: ClassificationAgent.Result,
        schemaKeys: [String],
        allowHeavyLLM: Bool,
        route: DocumentExtractionRouter.Route
    ) -> Result {
        var runtimeStatus: String?
        var usedSemanticExtractor = false
        var usedAI = false
        var usedHeuristicFallback = false
        var openType = classification.openDocumentType ?? inferredDocumentType(from: layout)

        let documentTypeHint = openType
        let machineReadable = MachineReadableFieldExtractor.extract(
            from: payloadHints,
            plainOCRText: layout.layoutText
        )
        let specialized = SpecializedDocumentExtractors.suggestions(
            layout: layout,
            openDocumentType: documentTypeHint,
            classification: classification
        )
        let onnxSuggestions = OpenVocabularyFieldExtractor.suggestions(
            from: layout,
            documentTypeHint: documentTypeHint
        )
        var suggestions = CoreIngestHTTPClient.mergeSuggestions(
            trusted: machineReadable.suggestions,
            supplemental: specialized
        )
        suggestions = CoreIngestHTTPClient.mergeSuggestions(
            trusted: suggestions,
            supplemental: onnxSuggestions
        )
        if !specialized.isEmpty {
            runtimeStatus = "known_fast:specialized:\(specialized.count)"
        }

        if !onnxSuggestions.isEmpty {
            usedSemanticExtractor = true
            usedAI = MiniLMOnnxFieldEmbedder.shared.isAvailable
            runtimeStatus = "known_fast:onnx:\(OnnxFieldLabelMapper.runtimeStatus())"
            openType = openType ?? documentTypeHint
        } else if !machineReadable.suggestions.isEmpty {
            runtimeStatus = "known_fast:machine_readable:\(machineReadable.sources.joined(separator: ","))"
        } else if MiniLMOnnxFieldEmbedder.shared.isAvailable {
            runtimeStatus = "known_fast:onnx:\(OnnxFieldLabelMapper.runtimeStatus()):no_pairs_mapped"
        }

        if needsMoreExtraction(suggestions, schemaKeys: schemaKeys),
           allowHeavyLLM,
           OnDeviceMemoryGuard.mayRunHeavyInference()
        {
            if let mapped = OnDeviceFieldMapper.mapFields(
                layoutText: layout.modelInput,
                profileSchemaKeys: schemaKeys
            ) {
                suggestions = CoreIngestHTTPClient.mergeSuggestions(trusted: suggestions, supplemental: mapped.suggestions)
                openType = openType ?? mapped.documentType
                usedAI = true
                usedSemanticExtractor = true
                runtimeStatus = "known_fast:llm_retry:\(mapped.llmRuntimeStatus)"
            }
        }

        if needsMoreExtraction(suggestions, schemaKeys: schemaKeys) {
            let heuristic = UniversalDocumentParser.parse(from: layout.layoutText)
            if !heuristic.isEmpty {
                suggestions = CoreIngestHTTPClient.mergeSuggestions(trusted: suggestions, supplemental: heuristic)
                usedHeuristicFallback = true
            }
        }

        return finalize(
            suggestions: suggestions,
            openType: openType,
            usedAI: usedAI,
            usedHeuristicFallback: usedHeuristicFallback,
            usedSemanticExtractor: usedSemanticExtractor,
            machineReadable: machineReadable,
            classification: classification,
            layout: layout,
            route: route,
            runtimeStatus: runtimeStatus
        )
    }

    // MARK: - Unknown semantic path

    private static func extractUnknownSemanticPath(
        layout: LayoutIntelligenceAgent.LayoutDocument,
        payloadHints: EmbeddedPayloadHints.Result,
        classification: ClassificationAgent.Result,
        schemaKeys: [String],
        allowHeavyLLM: Bool,
        route: DocumentExtractionRouter.Route
    ) -> Result {
        var runtimeStatus: String?
        var usedSemanticExtractor = false
        var usedAI = false
        var usedHeuristicFallback = false
        var openType = classification.openDocumentType ?? inferredDocumentType(from: layout)

        let machineReadable = MachineReadableFieldExtractor.extract(
            from: payloadHints,
            plainOCRText: layout.layoutText
        )
        let specialized = SpecializedDocumentExtractors.suggestions(
            layout: layout,
            openDocumentType: openType,
            classification: classification
        )
        var suggestions = CoreIngestHTTPClient.mergeSuggestions(
            trusted: machineReadable.suggestions,
            supplemental: specialized
        )
        if !machineReadable.suggestions.isEmpty {
            runtimeStatus = "unknown_semantic:machine_readable:\(machineReadable.sources.joined(separator: ","))"
        } else if !specialized.isEmpty {
            runtimeStatus = "unknown_semantic:specialized:\(specialized.count)"
        }

        let onnxSuggestions = OpenVocabularyFieldExtractor.suggestions(
            from: layout,
            documentTypeHint: openType
        )
        if !onnxSuggestions.isEmpty {
            suggestions = CoreIngestHTTPClient.mergeSuggestions(trusted: suggestions, supplemental: onnxSuggestions)
            usedSemanticExtractor = true
            usedAI = MiniLMOnnxFieldEmbedder.shared.isAvailable
            runtimeStatus = "unknown_semantic:onnx:\(onnxSuggestions.count)"
        }

        if allowHeavyLLM, OnDeviceMemoryGuard.mayRunHeavyInference() {
            let chunked = LayoutAwareSemanticExtractor.extract(
                layout: layout,
                classification: classification,
                schemaKeys: schemaKeys
            )
            if !chunked.isEmpty {
                suggestions = CoreIngestHTTPClient.mergeSuggestions(trusted: suggestions, supplemental: chunked)
                usedSemanticExtractor = true
                usedAI = true
                runtimeStatus = "unknown_semantic:layout_ai:\(chunked.count)"
            } else if let mapped = OnDeviceFieldMapper.mapFields(
                layoutText: layout.modelInput,
                profileSchemaKeys: schemaKeys
            ) {
                suggestions = CoreIngestHTTPClient.mergeSuggestions(trusted: suggestions, supplemental: mapped.suggestions)
                openType = openType ?? mapped.documentType
                usedAI = true
                usedSemanticExtractor = true
                runtimeStatus = "unknown_semantic:llm:\(mapped.llmRuntimeStatus)"
            }
        } else if runtimeStatus == nil {
            runtimeStatus = "unknown_semantic:heavy:deferred:\(OnDeviceMemoryGuard.skipTraceToken)"
        }

        if needsMoreExtraction(suggestions, schemaKeys: schemaKeys) {
            let heuristic = UniversalDocumentParser.parse(from: layout.layoutText)
            if !heuristic.isEmpty {
                suggestions = CoreIngestHTTPClient.mergeSuggestions(trusted: suggestions, supplemental: heuristic)
                usedHeuristicFallback = true
                runtimeStatus = (runtimeStatus ?? "unknown_semantic") + ":heuristic:\(heuristic.count)"
            }
        }

        if case .installed = ModelArtifactRegistry.loadState(for: .visionLanguage),
           needsMoreExtraction(suggestions, schemaKeys: schemaKeys),
           allowHeavyLLM,
           OnDeviceMemoryGuard.mayRunHeavyInference()
        {
            runtimeStatus = (runtimeStatus ?? "unknown_semantic") + ":vlm:slot_ready:not_wired"
        }

        return finalize(
            suggestions: suggestions,
            openType: openType,
            usedAI: usedAI,
            usedHeuristicFallback: usedHeuristicFallback,
            usedSemanticExtractor: usedSemanticExtractor,
            machineReadable: machineReadable,
            classification: classification,
            layout: layout,
            route: route,
            runtimeStatus: runtimeStatus
        )
    }

    // MARK: - Shared

    private static func finalize(
        suggestions: [OcrFieldSuggestion],
        openType: String?,
        usedAI: Bool,
        usedHeuristicFallback: Bool,
        usedSemanticExtractor: Bool,
        machineReadable: MachineReadableFieldExtractor.Result,
        classification: ClassificationAgent.Result,
        layout: LayoutIntelligenceAgent.LayoutDocument,
        route: DocumentExtractionRouter.Route,
        runtimeStatus: String?
    ) -> Result {
        let documentType = openType ?? classification.openDocumentType ?? "other"
        let learned = IncrementalLearningStore.learnedSuggestions(
            documentType: documentType,
            ocrText: layout.layoutText,
            existingKeys: Set(suggestions.map(\.profileKey))
        )
        var merged = suggestions
        if !learned.isEmpty {
            merged = CoreIngestHTTPClient.mergeSuggestions(trusted: merged, supplemental: learned)
        }

        let usedMachineReadablePayload = merged.contains {
            $0.mappingSource == .barcode || $0.mappingSource == .mrz
        }

        return Result(
            suggestions: merged,
            openDocumentType: openType,
            usedAI: usedAI,
            usedHeuristicFallback: usedHeuristicFallback,
            usedTemplateExtractor: false,
            usedSemanticExtractor: usedSemanticExtractor,
            usedMachineReadablePayload: usedMachineReadablePayload,
            learnedSuggestionCount: learned.count,
            onDeviceRuntimeStatus: runtimeStatus,
            extractionRoute: route
        )
    }

    private static func emptyResult(
        route: DocumentExtractionRouter.Route,
        runtimeStatus: String
    ) -> Result {
        Result(
            suggestions: [],
            openDocumentType: nil,
            usedAI: false,
            usedHeuristicFallback: false,
            usedTemplateExtractor: false,
            usedSemanticExtractor: false,
            usedMachineReadablePayload: false,
            learnedSuggestionCount: 0,
            onDeviceRuntimeStatus: runtimeStatus,
            extractionRoute: route
        )
    }

    private static func inferredDocumentType(from layout: LayoutIntelligenceAgent.LayoutDocument) -> String? {
        let inferred = ProfileSchemaKeysForDocument.inferOpenType(from: layout.layoutText + "\n" + layout.modelInput)
        return inferred == "other" ? nil : inferred
    }

    /// Continue extraction until a reasonable fraction of document-specific schema keys are filled.
    private static func needsMoreExtraction(_ suggestions: [OcrFieldSuggestion], schemaKeys: [String]) -> Bool {
        let keys = schemaKeys.isEmpty ? ProfileSchema.allFields.map(\.key) : schemaKeys
        guard !keys.isEmpty else { return suggestions.count < 4 }
        let filled = Set(suggestions.map(\.profileKey)).intersection(keys).count
        let target = max(4, Int(ceil(Double(keys.count) * 0.45)))
        return filled < target
    }
}
