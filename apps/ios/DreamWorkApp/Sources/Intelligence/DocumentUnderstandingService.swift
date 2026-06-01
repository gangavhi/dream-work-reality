import Foundation

/// Unified local document understanding pipeline (zero cloud egress).
///
/// Pipeline stages:
/// 1. Intake — images/PDF via `DocumentImportHelper` + `DocumentTextExtractor`
/// 2. Document type — `LocalDocumentClassifier` (+ optional GGUF classifier)
/// 3. OCR — Apple Vision via `OcrEngine` / `VisionOcrAdapter`
/// 4. Layout + semantics — `LayoutIntelligenceAgent`, `ExtractionAgent` (ONNX / GGUF / heuristics)
/// 5. Normalization — `FieldNormalizationEngine`
/// 6. Schema mapping — `SchemaMappingEngine` → standardized JSON
/// 7. Confidence — `ConfidenceOrchestrator`
/// 8. Profile storage — `PersonRecord` via Rust FFI on save
/// 9. Multi-document merge — `ProfileMergeEngine` + `PersonProfileMatcher`
enum DocumentUnderstandingService {
    struct PipelineResult: Hashable {
        let displayType: ScannedDocumentType
        let openDocumentType: String
        let suggestions: [OcrFieldSuggestion]
        let standardizedOutput: SchemaMappingEngine.StandardizedDocumentOutput
        let canonicalProfile: CanonicalIdentityProfile
        let fieldsRequiringReview: [String]
        let usedAI: Bool
        let pipelineTrace: [String]
        let ocrModelInput: String
        let ocrLabelValuePairs: String
    }

    static func process(
        document: VisionOcrAdapter.NormalizedDocument,
        fileURL: URL? = nil,
        allowHeavyLLM: Bool = true
    ) async -> PipelineResult {
        let orchestrated = await DocumentIntelligenceOrchestrator.process(
            document: document,
            fileURL: fileURL,
            allowHeavyLLM: allowHeavyLLM
        )

        let openType = orchestrated.openDocumentTypeLabel
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
        let standardized = orchestrated.standardizedOutput
            ?? SchemaMappingEngine.map(
                openDocumentType: orchestrated.openDocumentTypeLabel,
                suggestions: orchestrated.suggestions
            )

        return PipelineResult(
            displayType: orchestrated.displayType,
            openDocumentType: openType,
            suggestions: orchestrated.suggestions,
            standardizedOutput: standardized,
            canonicalProfile: CanonicalIdentityProfile.from(suggestions: orchestrated.suggestions),
            fieldsRequiringReview: standardized.fieldsRequiringReview,
            usedAI: orchestrated.usedAI,
            pipelineTrace: orchestrated.pipelineTrace,
            ocrModelInput: orchestrated.ocrModelInput,
            ocrLabelValuePairs: orchestrated.ocrLabelValuePairs
        )
    }

    static func averageOCRConfidence(document: VisionOcrAdapter.NormalizedDocument) -> Double {
        let blocks = document.pages.flatMap(\.blocks)
        guard !blocks.isEmpty else { return 0.65 }
        let total = blocks.reduce(0.0) { $0 + Double($1.confidence) }
        return min(1.0, max(0.35, total / Double(blocks.count)))
    }
}
