import Foundation

/// Single ingest path for all document scans/uploads (ADR §0 — no per-format parser routing).
enum DocumentIntelligencePipeline {
    struct Result: Hashable {
        let layoutText: String
        let plainText: String
        let displayType: ScannedDocumentType
        let openDocumentTypeLabel: String
        let suggestions: [OcrFieldSuggestion]
        let understanding: DocumentUnderstandingResult?
        let usedAI: Bool
    }

    static func extract(
        document: VisionOcrAdapter.NormalizedDocument,
        fileURL: URL? = nil
    ) async -> Result {
        let layoutText = OcrLayoutSerializer.serialize(document: document)
        let plainText = layoutText.trimmingCharacters(in: .whitespacesAndNewlines)
        let payloadHints = await EmbeddedPayloadHints.collect(fileURL: fileURL, layoutText: layoutText)
        let modelInput = OcrLayoutSerializer.modelInput(document: document, payloadHints: payloadHints)
        let schemaKeys = ProfileSchema.allFields.map(\.key)

        var suggestions: [OcrFieldSuggestion] = []
        var understanding: DocumentUnderstandingResult?
        var usedAI = false
        var openType: String?

        switch GenAISettings.provider {
        case .onDevice:
            if let mapped = OnDeviceFieldMapper.mapFields(layoutText: modelInput, profileSchemaKeys: schemaKeys) {
                suggestions = mapped.suggestions
                openType = mapped.documentType
                usedAI = true
            }
        case .localLLM:
            if let mapped = await GenAIFieldMapper.mapFields(
                layoutText: modelInput,
                profileSchemaKeys: schemaKeys
            ) {
                suggestions = mapped.suggestions
                openType = mapped.documentType
                usedAI = true
            }
        case .cloudLLMDevOnly:
            if let mapped = await GenAIFieldMapper.mapFields(
                layoutText: modelInput,
                profileSchemaKeys: schemaKeys
            ) {
                suggestions = mapped.suggestions
                openType = mapped.documentType
                usedAI = true
            }
        case .off:
            break
        }

        if suggestions.isEmpty, !plainText.isEmpty {
            suggestions = UniversalDocumentParser.parse(from: plainText)
        }

        if understanding == nil, usedAI, let openType {
            let presentation = DocumentTypePresentation.resolve(openType)
            understanding = DocumentUnderstandingResult(
                documentType: openType.isEmpty ? presentation.displayLabel : openType,
                documentTypeConfidence: GenAISettings.provider == .onDevice ? 0.82 : 0.92,
                issuerRegion: suggestions.first(where: { $0.profileKey == ProfileFieldKey.driversLicenseState })?.value,
                displayNameHint: suggestions.first(where: { $0.profileKey == ProfileFieldKey.displayName })?.value,
                usedAI: true
            )
        }

        let presentation = DocumentTypePresentation.resolve(openType)
        let displayType = presentation.enumType
        let label = openType.map { DocumentTypePresentation.resolve($0).displayLabel } ?? presentation.displayLabel

        suggestions = GenAIFieldMapper.finalizeSuggestions(suggestions, documentType: displayType)
        suggestions = PersonNameResolver.apply(to: suggestions, ocrText: plainText, documentType: displayType)

        return Result(
            layoutText: layoutText,
            plainText: plainText,
            displayType: displayType,
            openDocumentTypeLabel: label,
            suggestions: suggestions,
            understanding: understanding,
            usedAI: usedAI
        )
    }
}
