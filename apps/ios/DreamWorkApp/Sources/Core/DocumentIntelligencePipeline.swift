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
        let mappingNotice: String?
        let usedMachineReadablePayload: Bool
        let usedHeuristicFallback: Bool
        let knowledgeEntities: [KnowledgeEntity]
        let fraudFindings: [FraudDetectionAgent.Finding]
        let pipelineTrace: [String]
    }

    static func extract(
        document: VisionOcrAdapter.NormalizedDocument,
        fileURL: URL? = nil
    ) async -> Result {
        let orchestrated = await DocumentIntelligenceOrchestrator.process(
            document: document,
            fileURL: fileURL
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
            fraudFindings: orchestrated.fraudFindings,
            pipelineTrace: orchestrated.pipelineTrace
        )
    }
}
