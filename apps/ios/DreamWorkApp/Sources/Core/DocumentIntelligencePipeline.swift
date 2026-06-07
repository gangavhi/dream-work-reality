import Foundation

/// Single ingest path for scans/uploads — TrustNest rewrite v2 (on-device only, no orchestrator).
enum DocumentIntelligencePipeline {
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

    static func extract(
        document: VisionOcrAdapter.NormalizedDocument,
        fileURL: URL? = nil,
        allowHeavyLLM: Bool = true
    ) async -> Result {
        _ = allowHeavyLLM
        let (extracted, _) = await RewritePipeline.extract(document: document, fileURL: fileURL)
        return Result(
            layoutText: extracted.layoutText,
            plainText: extracted.plainText,
            displayType: extracted.displayType,
            openDocumentTypeLabel: extracted.openDocumentTypeLabel,
            suggestions: extracted.suggestions,
            understanding: extracted.understanding,
            usedAI: extracted.usedAI,
            mappingNotice: extracted.mappingNotice,
            usedMachineReadablePayload: extracted.usedMachineReadablePayload,
            usedHeuristicFallback: extracted.usedHeuristicFallback,
            knowledgeEntities: extracted.knowledgeEntities,
            identityGraph: extracted.identityGraph,
            autofillPayload: extracted.autofillPayload,
            fraudFindings: extracted.fraudFindings,
            pipelineTrace: extracted.pipelineTrace,
            ocrModelInput: extracted.ocrModelInput,
            ocrLabelValuePairs: extracted.ocrLabelValuePairs,
            standardizedOutput: extracted.standardizedOutput
        )
    }
}
