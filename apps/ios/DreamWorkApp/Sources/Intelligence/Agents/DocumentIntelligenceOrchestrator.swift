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
        let ocrModelInput: String
        let ocrLabelValuePairs: String
        let standardizedOutput: SchemaMappingEngine.StandardizedDocumentOutput?
    }

    static func process(
        document: VisionOcrAdapter.NormalizedDocument,
        fileURL: URL? = nil,
        allowHeavyLLM: Bool = true
    ) async -> Result {
        var trace: [String] = ["ocr:vision.en.v1"]

        let layoutText = OcrLayoutSerializer.serialize(document: document)
        let payloadHints = await EmbeddedPayloadHints.collect(fileURL: fileURL, layoutText: layoutText)
        if !payloadHints.mrzLines.isEmpty {
            trace.append("mrz:detected:\(payloadHints.mrzLines.count)")
        }
        if !payloadHints.barcodePayloads.isEmpty {
            trace.append("barcode:detected:\(payloadHints.barcodePayloads.count)")
        }

        let layout = LayoutIntelligenceAgent.analyze(document: document, payloadHints: payloadHints)
        trace.append("layout:\(layout.engineID)")

        let classification = LocalDocumentClassifier.classify(
            layoutText: layout.layoutText,
            modelInput: layout.modelInput,
            payloadHints: payloadHints,
            allowHeavyLLM: allowHeavyLLM
        )
        trace.append("classify:\(classification.engineID):\(classification.runtimeStatus)")

        let schemaKeys = ProfileSchemaKeysForDocument.keys(
            forOpenDocumentType: classification.openDocumentType,
            fallbackToAll: true
        )
        trace.append("schema_keys:\(schemaKeys.count)")

        let templateMatch: DocumentTemplateAgent.Match? = nil
        trace.append("template:disabled:ml_only")
        let strategy = ExtractionStrategyAgent.determine(
            layout: layout,
            classification: classification,
            payloadHints: payloadHints,
            templateMatch: templateMatch
        )
        trace.append("route:\(strategy.route.rawValue)")
        trace.append("strategy:\(strategy.structure.rawValue)")

        let extraction = await ExtractionAgent.extract(
            layout: layout,
            payloadHints: payloadHints,
            schemaKeys: schemaKeys,
            classification: classification,
            templateMatch: templateMatch,
            strategy: strategy,
            allowHeavyLLM: allowHeavyLLM
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
        if extraction.usedHeuristicFallback {
            trace.append("extract:heuristic_fallback")
        }
        trace.append("extract:route:\(extraction.extractionRoute.rawValue)")
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
        if isClassifierFailure(resolvedClassification.runtimeStatus),
           !resolvedClassification.runtimeStatus.hasPrefix("classifier_active:")
        {
            mappingNotice =
                "Document type could not be classified with high confidence. Review detected fields before saving."
        }
        if let runtimeStatus = extraction.onDeviceRuntimeStatus,
           runtimeStatus.contains("memory_guard")
        {
            mappingNotice = [
                mappingNotice,
                OnDeviceMemoryGuard.userFacingSkipNotice
            ].compactMap { $0 }.joined(separator: "\n")
        } else if let runtimeStatus = extraction.onDeviceRuntimeStatus,
                  isDocumentParserFailure(runtimeStatus)
        {
            mappingNotice =
                [
                    mappingNotice,
                    "The on-device LLM model meant for document data parsing failed. No heuristic fallback was used; try reinstalling the model or scanning again."
                ].compactMap { $0 }.joined(separator: "\n")
        }

        let suggestionsBeforeGrounding = ProfileSchema.sortSuggestions(extraction.suggestions)
        let validation = DocumentValidationPipeline.validate(
            suggestionsBeforeGrounding,
            documentType: resolvedClassification.enumType,
            ocrCorpus: layout.layoutText
        )
        if !validation.warnings.isEmpty {
            trace.append("validate:pipeline:\(validation.warnings.joined(separator: "|"))")
        }
        if !validation.rejectedKeys.isEmpty {
            trace.append("validate:rejected:\(validation.rejectedKeys.count)")
        }
        let grounded = validation.suggestions
        if grounded.count < suggestionsBeforeGrounding.count {
            trace.append("validate:grounding:filtered=\(suggestionsBeforeGrounding.count - grounded.count)")
        } else {
            trace.append("validate:grounding")
        }
        let mergedAddress = AddressFieldMerger.enrich(grounded, layout: layout)
        if mergedAddress.count > grounded.count {
            trace.append("address:merged:\(mergedAddress.count - grounded.count)")
        }

        let normalized = FieldNormalizationEngine.normalize(mergedAddress)
        trace.append("normalize:\(normalized.count)")

        let avgOCRConfidence = DocumentUnderstandingService.averageOCRConfidence(document: document)
        let confidenceScored = ConfidenceOrchestrator.enrich(
            normalized,
            documentType: resolvedClassification.enumType,
            ocrCorpus: layout.layoutText,
            averageOCRBlockConfidence: avgOCRConfidence
        )
        let reviewCount = confidenceScored.filter(\.requiresManualConfirmation).count
        trace.append("confidence:orchestrated:review=\(reviewCount)")

        let suggestions = confidenceScored
        let openTypeForSchema = extraction.openDocumentType
            ?? classification.openDocumentType
            ?? resolvedClassification.openDocumentType
            ?? "other"
        let standardizedOutput = SchemaMappingEngine.map(
            openDocumentType: openTypeForSchema,
            suggestions: suggestions
        )
        trace.append("schema:mapped:\(standardizedOutput.fields.filter { !$0.value.isEmpty }.count)")
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

        let labelValuePairsText = layout.labelValuePairs
            .map { "\($0.label) → \($0.value)" }
            .joined(separator: "\n")

        return Result(
            layoutText: layout.layoutText,
            plainText: layout.plainText,
            displayType: resolvedClassification.enumType,
            openDocumentTypeLabel: openTypeLabel,
            suggestions: suggestions,
            understanding: understanding,
            usedAI: extraction.usedAI,
            mappingNotice: mappingNotice,
            usedMachineReadablePayload: extraction.usedMachineReadablePayload,
            usedHeuristicFallback: extraction.usedHeuristicFallback,
            knowledgeEntities: identityGraph.entities,
            identityGraph: identityGraph,
            autofillPayload: identityGraph.autofillPayload,
            fraudFindings: [],
            pipelineTrace: trace,
            ocrModelInput: layout.modelInput,
            ocrLabelValuePairs: labelValuePairsText,
            standardizedOutput: standardizedOutput
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
            && !runtimeStatus.hasPrefix("classifier_active:")
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
