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
        let identityGraph: StructuredIdentityGraph
        let autofillPayload: SmartAutofillPayload
        let fraudFindings: [FraudDetectionAgent.Finding]
        let pipelineTrace: [String]
    }

    static func process(
        document: VisionOcrAdapter.NormalizedDocument,
        fileURL: URL? = nil
    ) async -> Result {
        var trace: [String] = ["ocr:vision.en.v1"]

        let payloadHints = EmbeddedPayloadHints.Result.empty
        let layout = LayoutIntelligenceAgent.analyze(document: document, payloadHints: payloadHints)
        trace.append("layout:\(layout.engineID)")

        let classification: ClassificationAgent.Result
        if GenAISettings.provider == .onDevice {
            classification = ClassificationAgent.pendingParserClassification()
            trace.append("classify:skipped:single_pass_parser")
        } else {
            classification = ClassificationAgent.classify(
                modelInput: layout.modelInput,
                mappedDocumentType: nil,
                machineReadableSources: []
            )
            trace.append("classify:\(classification.engineID):\(classification.runtimeStatus)")
        }
        let schemaKeys: [String] = []
        trace.append("schema_keys:generic:any")

        let templateMatch: DocumentTemplateAgent.Match? = nil
        trace.append("template:disabled:ml_only")
        let strategy = ExtractionStrategyAgent.determine(
            layout: layout,
            classification: classification,
            templateMatch: templateMatch
        )
        trace.append("strategy:\(strategy.structure.rawValue)")

        let extraction = await ExtractionAgent.extract(
            layout: layout,
            payloadHints: payloadHints,
            schemaKeys: schemaKeys,
            classification: classification,
            templateMatch: templateMatch,
            strategy: strategy
        )
        if extraction.usedTemplateExtractor {
            trace.append("extract:template")
        } else if extraction.usedSemanticExtractor {
            trace.append("extract:semantic")
        } else {
            trace.append("extract:\(extraction.usedAI ? "on_device" : "ml_failed")")
        }
        if extraction.learnedSuggestionCount > 0 {
            trace.append("learning:applied:\(extraction.learnedSuggestionCount)")
        }
        if let runtimeStatus = extraction.onDeviceRuntimeStatus {
            trace.append("runtime:\(runtimeStatus)")
        }

        let resolvedClassification = classificationFromExtraction(
            extraction: extraction,
            fallback: classification
        )
        if GenAISettings.provider == .onDevice {
            trace.append("classify:resolved:\(resolvedClassification.runtimeStatus)")
        }

        var mappingNotice: String?
        if isClassifierFailure(resolvedClassification.runtimeStatus) {
            mappingNotice =
                "The local ML model meant for document type classification failed. No machine-readable or keyword classifier fallback was used; install the classifier model or scan again."
        }
        if let runtimeStatus = extraction.onDeviceRuntimeStatus,
           isDocumentParserFailure(runtimeStatus)
        {
            mappingNotice =
                [
                    mappingNotice,
                    "The on-device LLM model meant for document data parsing failed. No heuristic fallback was used; try reinstalling the model or scanning again."
                ].compactMap { $0 }.joined(separator: "\n")
        }

        let suggestions = ProfileSchema.sortSuggestions(extraction.suggestions)
        trace.append("validate:ml_only")
        trace.append("confidence:model_output")
        trace.append("fraud:disabled_ml_only_pipeline")

        let openTypeLabel = resolvedClassification.displayLabel
        let understanding: DocumentUnderstandingResult? = {
            guard extraction.usedAI else { return nil }
            return DocumentUnderstandingResult(
                documentType: extraction.openDocumentType ?? resolvedClassification.openDocumentType ?? openTypeLabel,
                documentTypeConfidence: resolvedClassification.confidence,
                issuerRegion: suggestions.first(where: { $0.profileKey == ProfileFieldKey.driversLicenseState })?.value,
                displayNameHint: suggestions.first(where: { $0.profileKey == ProfileFieldKey.displayName })?.value,
                usedAI: extraction.usedAI
            )
        }()

        let graphDocumentType = extraction.openDocumentType ?? resolvedClassification.openDocumentType ?? "other"
        let identityGraph = DocumentKnowledgeGraph.buildIdentityGraph(
            from: suggestions,
            documentType: graphDocumentType
        )
        trace.append("identity_graph:\(identityGraph.entities.count)")
        VectorDocumentMemory.index(
            documentType: graphDocumentType,
            plainText: layout.plainText
        )
        trace.append("memory:vector_index")

        return Result(
            layoutText: layout.layoutText,
            plainText: layout.plainText,
            displayType: resolvedClassification.enumType,
            openDocumentTypeLabel: openTypeLabel,
            suggestions: suggestions,
            understanding: understanding,
            usedAI: extraction.usedAI,
            mappingNotice: mappingNotice,
            usedMachineReadablePayload: false,
            usedHeuristicFallback: extraction.usedHeuristicFallback,
            knowledgeEntities: identityGraph.entities,
            identityGraph: identityGraph,
            autofillPayload: identityGraph.autofillPayload,
            fraudFindings: [],
            pipelineTrace: trace
        )
    }

    private static func isDocumentParserFailure(_ runtimeStatus: String) -> Bool {
        runtimeStatus.contains("llm_document_parser_failed")
            || runtimeStatus.contains("gguf_valid_llama_cpp_generation_failed")
            || runtimeStatus.contains("gguf_valid_llama_cpp_no_fields")
    }

    private static func isClassifierFailure(_ runtimeStatus: String) -> Bool {
        runtimeStatus != "classifier_active"
            && runtimeStatus != "classifier_pending_parser"
    }

    private static func classificationFromExtraction(
        extraction: ExtractionAgent.Result,
        fallback: ClassificationAgent.Result
    ) -> ClassificationAgent.Result {
        guard GenAISettings.provider == .onDevice,
              let openType = extraction.openDocumentType?.trimmingCharacters(in: .whitespacesAndNewlines),
              !openType.isEmpty
        else {
            return fallback
        }
        let presentation = DocumentTypePresentation.resolve(openType)
        return ClassificationAgent.Result(
            openDocumentType: openType,
            displayLabel: presentation.displayLabel,
            enumType: presentation.enumType,
            confidence: extraction.usedAI ? 0.72 : 0,
            engineID: ModelArtifactSlot.generativeLLM.rawValue,
            issuerRegion: nil,
            country: nil,
            runtimeStatus: extraction.usedAI ? "classifier_active" : "classifier_pending_parser"
        )
    }
}

private extension LayoutIntelligenceAgent.LayoutDocument {
    var plainText: String {
        layoutText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
