import Foundation

/// Coordinates standalone agents for document intelligence (zero egress default).
enum DocumentIntelligenceOrchestrator {
    struct Result: Hashable {
        let layoutText: String
        let plainText: String
        let displayType: ScannedDocumentType
        let openDocumentTypeLabel: String
        let suggestions: [OcrFieldSuggestion]
        let understanding: DocumentUnderstandingResult?
        let usedAI: Bool
        let mappingNotice: String?
        let usedMachineReadablePayload: Bool
        let usedHeuristicFallback: Bool
        let knowledgeEntities: [KnowledgeEntity]
        let fraudFindings: [FraudDetectionAgent.Finding]
        let pipelineTrace: [String]
    }

    static func process(
        document: VisionOcrAdapter.NormalizedDocument,
        fileURL: URL? = nil
    ) async -> Result {
        var trace: [String] = ["ocr:vision.en.v1"]

        let payloadHints = await EmbeddedPayloadHints.collect(
            fileURL: fileURL,
            layoutText: OcrLayoutSerializer.serialize(document: document)
        )
        let layout = LayoutIntelligenceAgent.analyze(document: document, payloadHints: payloadHints)
        trace.append("layout:\(layout.engineID)")

        let inferredType = ProfileSchemaKeysForDocument.inferOpenType(from: layout.modelInput)
        let schemaKeys = ProfileSchemaKeysForDocument.keys(forOpenDocumentType: inferredType)

        let machineReadable = MachineReadableFieldExtractor.extract(
            from: payloadHints,
            supplementalOCRText: layout.modelInput
        )
        let extraction = await ExtractionAgent.extract(
            layout: layout,
            payloadHints: payloadHints,
            schemaKeys: schemaKeys
        )
        trace.append("extract:\(extraction.usedAI ? "on_device" : "heuristic")")

        let classification = ClassificationAgent.classify(
            modelInput: layout.modelInput,
            mappedDocumentType: extraction.openDocumentType,
            machineReadableSources: machineReadable.sources
        )
        trace.append("classify:\(classification.engineID)")

        var mappingNotice: String?
        if extraction.networkLLMFailed {
            mappingNotice =
                "Network model unavailable — using on-device mapping. For Ollama on a phone, set your Mac's Wi‑Fi IP in Settings (not 127.0.0.1)."
        } else if extraction.usedHeuristicFallback, !machineReadable.decodedPayload, GenAISettings.provider == .onDevice {
            mappingNotice =
                "Fields are estimated from text patterns. Review each value against the scan — accuracy improves when labels are clear on the document."
        }

        var suggestions = extraction.suggestions
        suggestions = GenAIFieldMapper.finalizeSuggestions(suggestions, documentType: classification.enumType)
        suggestions = NameFieldReconciler.reconcile(suggestions)

        let trustedKeys = Set(machineReadable.suggestions.map(\.profileKey))
        let ocrCorpus = layout.plainText + "\n" + layout.layoutText
        suggestions = OcrGroundingValidator.filter(
            suggestions,
            ocrCorpus: ocrCorpus,
            trustedProfileKeys: trustedKeys
        )
        trace.append("validate:grounding")

        let avgOCR = averageOCRConfidence(document: document)
        suggestions = ConfidenceOrchestrator.enrich(
            suggestions,
            documentType: classification.enumType,
            ocrCorpus: ocrCorpus,
            averageOCRBlockConfidence: avgOCR
        )
        trace.append("confidence:orchestrated")

        let fraudFindings = FraudDetectionAgent.analyze(fileURL: fileURL, plainText: layout.plainText)
        if !fraudFindings.isEmpty { trace.append("fraud:heuristic") }

        let openTypeLabel = classification.displayLabel
        let understanding: DocumentUnderstandingResult? = {
            guard extraction.usedAI || machineReadable.decodedPayload else { return nil }
            return DocumentUnderstandingResult(
                documentType: classification.openDocumentType ?? openTypeLabel,
                documentTypeConfidence: classification.confidence,
                issuerRegion: suggestions.first(where: { $0.profileKey == ProfileFieldKey.driversLicenseState })?.value,
                displayNameHint: suggestions.first(where: { $0.profileKey == ProfileFieldKey.displayName })?.value,
                usedAI: extraction.usedAI
            )
        }()

        let entities = DocumentKnowledgeGraph.entities(
            from: suggestions,
            documentType: classification.openDocumentType ?? "other"
        )
        VectorDocumentMemory.index(
            documentType: classification.openDocumentType ?? "other",
            plainText: layout.plainText
        )
        trace.append("memory:vector_index")

        return Result(
            layoutText: layout.layoutText,
            plainText: layout.plainText,
            displayType: classification.enumType,
            openDocumentTypeLabel: openTypeLabel,
            suggestions: suggestions,
            understanding: understanding,
            usedAI: extraction.usedAI,
            mappingNotice: mappingNotice,
            usedMachineReadablePayload: machineReadable.decodedPayload,
            usedHeuristicFallback: extraction.usedHeuristicFallback,
            knowledgeEntities: entities,
            fraudFindings: fraudFindings,
            pipelineTrace: trace
        )
    }

    private static func averageOCRConfidence(document: VisionOcrAdapter.NormalizedDocument) -> Double {
        let scores = document.pages.flatMap(\.blocks).map { Double($0.confidence) }
        guard !scores.isEmpty else { return 0.75 }
        return scores.reduce(0, +) / Double(scores.count)
    }
}

private extension LayoutIntelligenceAgent.LayoutDocument {
    var plainText: String {
        layoutText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
