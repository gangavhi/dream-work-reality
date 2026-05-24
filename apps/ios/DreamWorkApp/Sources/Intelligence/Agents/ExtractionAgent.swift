import Foundation

/// Hybrid extraction for **any** document: open-vocabulary layout → machine-readable boosters → on-device mapper → regex fallback.
enum ExtractionAgent {
    struct Result: Hashable {
        var suggestions: [OcrFieldSuggestion]
        var openDocumentType: String?
        var usedAI: Bool
        var usedHeuristicFallback: Bool
    }

    static func extract(
        layout: LayoutIntelligenceAgent.LayoutDocument,
        payloadHints: EmbeddedPayloadHints.Result,
        schemaKeys: [String]
    ) async -> Result {
        let typeHint = ProfileSchemaKeysForDocument.inferOpenType(from: layout.layoutText)

        var suggestions = OpenVocabularyFieldExtractor.suggestions(
            from: layout,
            documentTypeHint: typeHint == "other" ? nil : typeHint
        )

        let machineReadable = MachineReadableFieldExtractor.extract(
            from: payloadHints,
            plainOCRText: layout.layoutText
        )
        suggestions = mergeSupplemental(primary: machineReadable.suggestions, supplemental: suggestions)

        var usedAI = !suggestions.isEmpty
        var openType = openDocumentType(from: machineReadable) ?? (typeHint == "other" ? nil : typeHint)
        var usedHeuristicFallback = false

        let mapperKeys = schemaKeys.isEmpty
            ? ProfileSchema.allFields.map(\.key)
            : schemaKeys

        switch GenAISettings.provider {
        case .onDevice:
            if let mapped = OnDeviceFieldMapper.mapFields(
                layoutText: layout.modelInput,
                profileSchemaKeys: mapperKeys
            ) {
                suggestions = mergeSupplemental(primary: suggestions, supplemental: mapped.suggestions)
                openType = openType ?? mapped.documentType
                usedAI = true
            } else if suggestions.isEmpty {
                usedHeuristicFallback = true
            }
        case .off:
            break
        }

        let plain = layout.layoutText.trimmingCharacters(in: .whitespacesAndNewlines)
        if suggestions.isEmpty, !plain.isEmpty {
            suggestions = UniversalDocumentParser.parse(from: plain)
            usedHeuristicFallback = true
        }

        return Result(
            suggestions: applyNERStub(layoutText: layout.modelInput, existing: suggestions),
            openDocumentType: openType,
            usedAI: usedAI,
            usedHeuristicFallback: usedHeuristicFallback
        )
    }

    private static func openDocumentType(from machineReadable: MachineReadableFieldExtractor.Result) -> String? {
        if machineReadable.sources.contains("passport") { return "passport" }
        if machineReadable.sources.contains("pdf417") || machineReadable.sources.contains("drivers_license") {
            return "drivers_license"
        }
        return nil
    }

    private static func applyNERStub(
        layoutText: String,
        existing: [OcrFieldSuggestion]
    ) -> [OcrFieldSuggestion] {
        guard case .installed = ModelArtifactRegistry.loadState(for: .nerDistilBERT) else {
            return existing
        }
        return existing
    }

    private static func mergeSupplemental(
        primary: [OcrFieldSuggestion],
        supplemental: [OcrFieldSuggestion]
    ) -> [OcrFieldSuggestion] {
        CoreIngestHTTPClient.mergeSuggestions(trusted: primary, supplemental: supplemental)
    }
}
