import Foundation

/// TrustNest rewrite v2 — 6-step on-device pipeline (no orchestrator, no remote AI).
enum RewritePipeline {
    struct Context: Hashable {
        let stashedSubmissionDocId: String?
        let formRelevant: Bool
        let canonicalDocumentType: String
    }

    static func extract(
        document: VisionOcrAdapter.NormalizedDocument,
        fileURL: URL? = nil
    ) async -> (result: DocumentIntelligencePipeline.Result, context: Context) {
        var trace = ["rewrite:v2", "step:1_capture"]

        // Step 2 — OCR (already normalized)
        let layoutText = OcrLayoutSerializer.serialize(document: document)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let plainText = layoutText
        trace.append("step:2_ocr")

        let payloadHints = await EmbeddedPayloadHints.collect(fileURL: fileURL, layoutText: layoutText)
        let layoutBlocks = OcrLayoutSerializer.orderedBlocks(from: document)

        // Step 3 — CLASSIFY (Layer A): heuristic → optional Create ML → layout fallbacks
        let ocrForClassify = plainText.isEmpty ? layoutText : plainText
        var classification = DocumentTypeClassifier.classify(from: ocrForClassify)
        if let createML = StandaloneDocumentTypeClassifier.classifyIfNeeded(
            ocrText: ocrForClassify,
            heuristic: classification
        ) {
            classification = createML
            trace.append("step:3_classify:createml")
        }
        if classification.documentType == .other,
           UniversalDocumentParser.looksLikeSSNDocument(ocrForClassify)
        {
            classification = DocumentClassification(
                documentType: .ssnCard,
                confidence: 0.9,
                matchedSignals: ["SSA card layout fallback"]
            )
        }
        if classification.documentType == .other,
           InsuranceCardParser.isInsuranceCard(ocrForClassify)
        {
            classification = DocumentClassification(
                documentType: .insuranceCard,
                confidence: 0.9,
                matchedSignals: ["insurance card layout fallback"]
            )
        }
        let canonicalType = RewriteStashPolicy.canonicalType(
            for: classification.documentType,
            ocrText: ocrForClassify
        )
        let formRelevant = RewriteStashPolicy.isFormRelevant(documentType: canonicalType)
        trace.append("step:3_classify:\(canonicalType)")

        // Step 4 — STASH? (metadata recorded on profile save; bytes prepared here)
        let shouldStash = RewriteStashPolicy.shouldStash(documentType: canonicalType) && fileURL != nil
        trace.append(shouldStash ? "step:4_stash:pending_save" : "step:4_stash:skip")

        // Step 5 — EXTRACT? (Layer C)
        let machineReadable = MachineReadableFieldExtractor.extract(
            from: payloadHints,
            plainOCRText: plainText
        )
        var suggestions: [OcrFieldSuggestion] = []
        if formRelevant {
            suggestions = RewriteFieldExtractor.extract(
                from: plainText.isEmpty ? layoutText : plainText,
                documentType: classification.documentType,
                machineReadable: machineReadable
            )
            trace.append("step:5_extract:\(suggestions.count)_fields")
        } else {
            trace.append("step:5_extract:skipped_not_form_relevant")
        }

        suggestions = PersonNameResolver.apply(
            to: suggestions,
            ocrText: plainText.isEmpty ? layoutText : plainText,
            documentType: classification.documentType
        )

        let usedMRZ = machineReadable.decodedPayload
        let usedHeuristic = !usedMRZ && !suggestions.isEmpty

        let understanding = DocumentUnderstandingResult(
            documentType: DocumentTypeClassifier.mapToUnderstandingType(classification.documentType),
            documentTypeConfidence: classification.confidence,
            issuerRegion: nil,
            displayNameHint: nil,
            usedAI: false
        )

        let identityGraph = DocumentKnowledgeGraph.buildIdentityGraph(
            from: suggestions,
            documentType: understanding.documentType
        )

        let result = DocumentIntelligencePipeline.Result(
            layoutText: layoutText,
            plainText: plainText.isEmpty ? layoutText : plainText,
            displayType: classification.documentType,
            openDocumentTypeLabel: RewriteStashPolicy.displayLabel(for: canonicalType),
            suggestions: suggestions,
            understanding: understanding,
            usedAI: false,
            mappingNotice: formRelevant
                ? nil
                : "Document saved on device. No typed fields extracted for this document type (v1).",
            usedMachineReadablePayload: usedMRZ,
            usedHeuristicFallback: usedHeuristic,
            knowledgeEntities: [],
            identityGraph: identityGraph,
            autofillPayload: identityGraph.autofillPayload,
            fraudFindings: [],
            pipelineTrace: trace,
            ocrModelInput: OcrLayoutSerializer.modelInput(document: document, payloadHints: payloadHints),
            ocrLabelValuePairs: OcrLayoutSerializer.labelValuePairs(from: layoutBlocks)
                .map { "\($0.label) → \($0.value)" }
                .joined(separator: "\n"),
            standardizedOutput: nil
        )

        let context = Context(
            stashedSubmissionDocId: nil,
            formRelevant: formRelevant,
            canonicalDocumentType: canonicalType
        )
        return (result, context)
    }
}
