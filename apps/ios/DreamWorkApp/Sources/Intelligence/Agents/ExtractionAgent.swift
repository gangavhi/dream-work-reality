import Foundation

/// Field extraction via Vision layout + NaturalLanguage (no ONNX / GGUF).
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
        _ = allowHeavyLLM

        let resolvedSchemaKeys = schemaKeys.isEmpty
            ? ProfileSchema.allFields.map(\.key)
            : schemaKeys

        switch strategy.route {
        case .knownFastPath:
            return await extractPath(
                layout: layout,
                payloadHints: payloadHints,
                classification: classification,
                schemaKeys: resolvedSchemaKeys,
                route: strategy.route,
                statusPrefix: "known_fast"
            )
        case .unknownSemantic:
            return await extractPath(
                layout: layout,
                payloadHints: payloadHints,
                classification: classification,
                schemaKeys: resolvedSchemaKeys,
                route: strategy.route,
                statusPrefix: "unknown_semantic"
            )
        }
    }

    private static func extractPath(
        layout: LayoutIntelligenceAgent.LayoutDocument,
        payloadHints: EmbeddedPayloadHints.Result,
        classification: ClassificationAgent.Result,
        schemaKeys: [String],
        route: DocumentExtractionRouter.Route,
        statusPrefix: String
    ) async -> Result {
        var runtimeStatus: String?
        var usedSemanticExtractor = false
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
            runtimeStatus = "\(statusPrefix):machine_readable:\(machineReadable.sources.joined(separator: ","))"
        } else if !specialized.isEmpty {
            runtimeStatus = "\(statusPrefix):specialized:\(specialized.count)"
        }

        let semantic = AppleSemanticFieldExtractor.suggestions(
            from: layout,
            documentTypeHint: openType
        )
        if !semantic.isEmpty {
            suggestions = CoreIngestHTTPClient.mergeSuggestions(trusted: suggestions, supplemental: semantic)
            usedSemanticExtractor = true
            runtimeStatus = (runtimeStatus ?? statusPrefix) + ":nl:\(semantic.count)"
        }

        if needsMoreExtraction(suggestions, schemaKeys: schemaKeys) {
            let heuristic = UniversalDocumentParser.parse(from: layout.layoutText)
            if !heuristic.isEmpty {
                suggestions = CoreIngestHTTPClient.mergeSuggestions(trusted: suggestions, supplemental: heuristic)
                usedHeuristicFallback = true
                runtimeStatus = (runtimeStatus ?? statusPrefix) + ":heuristic:\(heuristic.count)"
            }
        }

        if GenAISettings.shouldUseOptionalNetworkLLM,
           needsMoreExtraction(suggestions, schemaKeys: schemaKeys),
           let mapped = await GenAIFieldMapper.mapFields(
               layoutText: layout.modelInput,
               profileSchemaKeys: schemaKeys
           )
        {
            suggestions = CoreIngestHTTPClient.mergeSuggestions(trusted: suggestions, supplemental: mapped.suggestions)
            openType = openType ?? mapped.documentType
            runtimeStatus = (runtimeStatus ?? statusPrefix) + ":network_llm"
        }

        return finalize(
            suggestions: suggestions,
            openType: openType,
            usedAI: false,
            usedHeuristicFallback: usedHeuristicFallback,
            usedSemanticExtractor: usedSemanticExtractor,
            machineReadable: machineReadable,
            classification: classification,
            layout: layout,
            route: route,
            runtimeStatus: runtimeStatus
        )
    }

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

    private static func inferredDocumentType(from layout: LayoutIntelligenceAgent.LayoutDocument) -> String? {
        let inferred = ProfileSchemaKeysForDocument.inferOpenType(from: layout.layoutText + "\n" + layout.modelInput)
        return inferred == "other" ? nil : inferred
    }

    private static func needsMoreExtraction(_ suggestions: [OcrFieldSuggestion], schemaKeys: [String]) -> Bool {
        let keys = schemaKeys.isEmpty ? ProfileSchema.allFields.map(\.key) : schemaKeys
        guard !keys.isEmpty else { return suggestions.count < 4 }
        let filled = Set(suggestions.map(\.profileKey)).intersection(keys).count
        let target = max(4, Int(ceil(Double(keys.count) * 0.45)))
        return filled < target
    }
}
