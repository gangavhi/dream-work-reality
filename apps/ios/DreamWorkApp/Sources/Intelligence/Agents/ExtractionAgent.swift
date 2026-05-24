import Foundation

/// Hybrid extraction: machine-readable decode, on-device Rust mapper, optional network LLM, regex fallback.
enum ExtractionAgent {
    struct Result: Hashable {
        var suggestions: [OcrFieldSuggestion]
        var openDocumentType: String?
        var usedAI: Bool
        var usedHeuristicFallback: Bool
        var networkLLMFailed: Bool
    }

    static func extract(
        layout: LayoutIntelligenceAgent.LayoutDocument,
        payloadHints: EmbeddedPayloadHints.Result,
        schemaKeys: [String]
    ) async -> Result {
        let machineReadable = MachineReadableFieldExtractor.extract(
            from: payloadHints,
            supplementalOCRText: layout.modelInput
        )

        var suggestions = machineReadable.suggestions
        suggestions = merge(
            suggestions,
            LayoutIntelligenceAgent.suggestionsFromLayoutPairs(layout.labelValuePairs)
        )

        var usedAI = machineReadable.decodedPayload
        var openType: String?
        var usedHeuristicFallback = false
        var networkLLMFailed = false

        if machineReadable.decodedPayload {
            if machineReadable.sources.contains("mrz") { openType = "passport" }
            else if machineReadable.sources.contains("pdf417") { openType = "drivers_license" }
        }

        switch GenAISettings.provider {
        case .onDevice:
            if let mapped = OnDeviceFieldMapper.mapFields(
                layoutText: layout.modelInput,
                profileSchemaKeys: schemaKeys
            ) {
                suggestions = mergeSupplemental(primary: suggestions, supplemental: mapped.suggestions)
                openType = openType ?? mapped.documentType
                usedAI = true
            } else if suggestions.isEmpty {
                usedHeuristicFallback = true
            }
        case .localLLM, .cloudLLMDevOnly:
            if GenAISettings.activeLLMConfig != nil {
                if let mapped = await GenAIFieldMapper.mapFields(
                    layoutText: layout.modelInput,
                    profileSchemaKeys: schemaKeys
                ) {
                    suggestions = mergeSupplemental(primary: suggestions, supplemental: mapped.suggestions)
                    openType = openType ?? mapped.documentType
                    usedAI = true
                } else {
                    networkLLMFailed = true
                    if let mapped = OnDeviceFieldMapper.mapFields(
                        layoutText: layout.modelInput,
                        profileSchemaKeys: schemaKeys
                    ) {
                        suggestions = mergeSupplemental(primary: suggestions, supplemental: mapped.suggestions)
                        openType = openType ?? mapped.documentType
                        usedAI = true
                    }
                    usedHeuristicFallback = true
                }
            } else if let mapped = OnDeviceFieldMapper.mapFields(
                layoutText: layout.modelInput,
                profileSchemaKeys: schemaKeys
            ) {
                suggestions = mergeSupplemental(primary: suggestions, supplemental: mapped.suggestions)
                openType = openType ?? mapped.documentType
                usedAI = true
            }
        case .off:
            break
        }

        let plain = layout.layoutText.trimmingCharacters(in: .whitespacesAndNewlines)
        if suggestions.isEmpty, !plain.isEmpty {
            suggestions = UniversalDocumentParser.parse(from: plain)
            usedHeuristicFallback = true
        }

        suggestions = applyNERStub(layoutText: layout.modelInput, existing: suggestions)

        return Result(
            suggestions: suggestions,
            openDocumentType: openType,
            usedAI: usedAI,
            usedHeuristicFallback: usedHeuristicFallback,
            networkLLMFailed: networkLLMFailed
        )
    }

    /// DistilBERT NER slot — returns empty until `ner.distilbert.v1` CoreML is bundled.
    private static func applyNERStub(
        layoutText: String,
        existing: [OcrFieldSuggestion]
    ) -> [OcrFieldSuggestion] {
        guard case .installed = ModelArtifactRegistry.loadState(for: .nerDistilBERT) else {
            return existing
        }
        return existing
    }

    private static func merge(
        _ a: [OcrFieldSuggestion],
        _ b: [OcrFieldSuggestion]
    ) -> [OcrFieldSuggestion] {
        CoreIngestHTTPClient.mergeSuggestions(trusted: a, supplemental: b)
    }

    private static func mergeSupplemental(
        primary: [OcrFieldSuggestion],
        supplemental: [OcrFieldSuggestion]
    ) -> [OcrFieldSuggestion] {
        CoreIngestHTTPClient.mergeSuggestions(trusted: primary, supplemental: supplemental)
    }
}
