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
        /// User-visible notice when network LLM was configured but failed, or mapping is heuristic-only.
        let mappingNotice: String?
        let usedMachineReadablePayload: Bool
        let usedHeuristicFallback: Bool
    }

    static func extract(
        document: VisionOcrAdapter.NormalizedDocument,
        fileURL: URL? = nil
    ) async -> Result {
        let layoutText = OcrLayoutSerializer.serialize(document: document)
        let plainText = layoutText.trimmingCharacters(in: .whitespacesAndNewlines)
        let payloadHints = await EmbeddedPayloadHints.collect(fileURL: fileURL, layoutText: layoutText)
        let modelInput = OcrLayoutSerializer.modelInput(document: document, payloadHints: payloadHints)
        let schemaKeys = ProfileSchemaKeysForDocument.keys(
            forOpenDocumentType: ProfileSchemaKeysForDocument.inferOpenType(from: modelInput)
        )

        let machineReadable = MachineReadableFieldExtractor.extract(
            from: payloadHints,
            supplementalOCRText: modelInput
        )

        var suggestions = machineReadable.suggestions
        var usedAI = machineReadable.decodedPayload
        var openType: String?
        var understanding: DocumentUnderstandingResult?
        var mappingNotice: String?
        var usedHeuristicFallback = false
        var networkLLMFailed = false

        if machineReadable.decodedPayload {
            if machineReadable.sources.contains("mrz") {
                openType = IndianPassportParser.isIndianPassport(modelInput) ? "passport" : "passport"
            } else if machineReadable.sources.contains("pdf417") {
                openType = "drivers_license"
            }
        }

        switch GenAISettings.provider {
        case .onDevice:
            if let mapped = OnDeviceFieldMapper.mapFields(layoutText: modelInput, profileSchemaKeys: schemaKeys) {
                suggestions = mergeSupplemental(primary: suggestions, supplemental: mapped.suggestions)
                openType = openType ?? mapped.documentType
                usedAI = true
            } else if suggestions.isEmpty {
                usedHeuristicFallback = true
            }
        case .localLLM, .cloudLLMDevOnly:
            if GenAISettings.activeLLMConfig != nil {
                if let mapped = await GenAIFieldMapper.mapFields(
                    layoutText: modelInput,
                    profileSchemaKeys: schemaKeys
                ) {
                    suggestions = mergeSupplemental(primary: suggestions, supplemental: mapped.suggestions)
                    openType = openType ?? mapped.documentType
                    usedAI = true
                } else {
                    networkLLMFailed = true
                    if let mapped = OnDeviceFieldMapper.mapFields(
                        layoutText: modelInput,
                        profileSchemaKeys: schemaKeys
                    ) {
                        suggestions = mergeSupplemental(primary: suggestions, supplemental: mapped.suggestions)
                        openType = openType ?? mapped.documentType
                        usedAI = true
                    }
                    usedHeuristicFallback = true
                }
            } else if let mapped = OnDeviceFieldMapper.mapFields(
                layoutText: modelInput,
                profileSchemaKeys: schemaKeys
            ) {
                suggestions = mergeSupplemental(primary: suggestions, supplemental: mapped.suggestions)
                openType = openType ?? mapped.documentType
                usedAI = true
            }
        case .off:
            break
        }

        if suggestions.isEmpty, !plainText.isEmpty {
            suggestions = UniversalDocumentParser.parse(from: plainText)
            usedHeuristicFallback = true
        }

        if networkLLMFailed {
            mappingNotice =
                "Network model unavailable — using on-device mapping. For Ollama on a phone, set your Mac's Wi‑Fi IP in Settings (not 127.0.0.1)."
        } else if usedHeuristicFallback, !machineReadable.decodedPayload, GenAISettings.provider == .onDevice {
            mappingNotice =
                "Fields are estimated from text patterns. Review each value against the scan — accuracy improves when labels are clear on the document."
        }

        if understanding == nil, usedAI || machineReadable.decodedPayload, let openType {
            let presentation = DocumentTypePresentation.resolve(openType)
            understanding = DocumentUnderstandingResult(
                documentType: openType.isEmpty ? presentation.displayLabel : openType,
                documentTypeConfidence: machineReadable.decodedPayload ? 0.94 : (GenAISettings.provider == .onDevice ? 0.82 : 0.92),
                issuerRegion: suggestions.first(where: { $0.profileKey == ProfileFieldKey.driversLicenseState })?.value,
                displayNameHint: suggestions.first(where: { $0.profileKey == ProfileFieldKey.displayName })?.value,
                usedAI: usedAI
            )
        }

        let presentation = DocumentTypePresentation.resolve(openType)
        let displayType = machineReadable.decodedPayload && machineReadable.sources.contains("pdf417")
            ? .driversLicense
            : presentation.enumType
        let label = openType.map { DocumentTypePresentation.resolve($0).displayLabel } ?? presentation.displayLabel

        suggestions = GenAIFieldMapper.finalizeSuggestions(suggestions, documentType: displayType)
        suggestions = NameFieldReconciler.reconcile(suggestions)

        let trustedKeys = Set(machineReadable.suggestions.map(\.profileKey))
        let ocrCorpus = plainText + "\n" + layoutText
        suggestions = OcrGroundingValidator.filter(
            suggestions,
            ocrCorpus: ocrCorpus,
            trustedProfileKeys: trustedKeys
        )

        return Result(
            layoutText: layoutText,
            plainText: plainText,
            displayType: displayType,
            openDocumentTypeLabel: label,
            suggestions: suggestions,
            understanding: understanding,
            usedAI: usedAI,
            mappingNotice: mappingNotice,
            usedMachineReadablePayload: machineReadable.decodedPayload,
            usedHeuristicFallback: usedHeuristicFallback
        )
    }

    private static func mergeSupplemental(
        primary: [OcrFieldSuggestion],
        supplemental: [OcrFieldSuggestion]
    ) -> [OcrFieldSuggestion] {
        CoreIngestHTTPClient.mergeSuggestions(trusted: primary, supplemental: supplemental)
    }
}
