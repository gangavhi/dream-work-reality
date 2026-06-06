import Foundation

/// Single ingest path for scans/uploads — Vision OCR + Intelligence orchestrator (Apple NL, no GGUF/ONNX).
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
        let orchestrated = await DocumentIntelligenceOrchestrator.process(
            document: document,
            fileURL: fileURL,
            allowHeavyLLM: allowHeavyLLM
        )
        return Result(
            layoutText: orchestrated.layoutText,
            plainText: orchestrated.plainText,
            displayType: orchestrated.displayType,
            openDocumentTypeLabel: orchestrated.openDocumentTypeLabel,
            suggestions: orchestrated.suggestions,
            understanding: orchestrated.understanding,
            usedAI: orchestrated.usedAI,
            mappingNotice: orchestrated.mappingNotice,
            usedMachineReadablePayload: orchestrated.usedMachineReadablePayload,
            usedHeuristicFallback: orchestrated.usedHeuristicFallback,
            knowledgeEntities: orchestrated.knowledgeEntities,
            identityGraph: orchestrated.identityGraph,
            autofillPayload: orchestrated.autofillPayload,
            fraudFindings: orchestrated.fraudFindings,
            pipelineTrace: orchestrated.pipelineTrace,
            ocrModelInput: orchestrated.ocrModelInput,
            ocrLabelValuePairs: orchestrated.ocrLabelValuePairs,
            standardizedOutput: orchestrated.standardizedOutput
        )
    }
}
