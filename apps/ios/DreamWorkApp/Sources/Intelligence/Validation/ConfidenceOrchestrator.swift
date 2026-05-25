import Foundation

/// Multi-signal confidence before autofill / save (OCR + semantic + validation + grounding).
enum ConfidenceOrchestrator {
    struct Breakdown: Hashable {
        let ocrScore: Double
        let semanticScore: Double
        let validationScore: Double
        let groundingScore: Double
        let compositeScore: Double
        let requiresManualConfirmation: Bool
        let signals: [String]
    }

    static let manualConfirmationThreshold = 0.72

    static func score(
        suggestion: OcrFieldSuggestion,
        documentType: ScannedDocumentType,
        ocrCorpus: String,
        averageOCRBlockConfidence: Double
    ) -> Breakdown {
        var signals: [String] = []

        let ocrScore = min(1.0, max(0.35, averageOCRBlockConfidence))
        signals.append("ocr:\(String(format: "%.2f", ocrScore))")

        let semanticScore = semanticScoreFor(source: suggestion.mappingSource, base: suggestion.confidenceScore)
        signals.append("semantic:\(String(format: "%.2f", semanticScore))")

        let validationScore = ScanFieldValidator.isValid(suggestion, documentType: documentType) ? 1.0 : 0.35
        if validationScore < 1 { signals.append("validation:failed") }

        let groundingScore = OcrGroundingValidator.isGrounded(value: suggestion.value, in: normalize(corpus: ocrCorpus))
            || suggestion.mappingSource == .barcode
            || suggestion.mappingSource == .mrz
            ? 1.0
            : 0.4
        if groundingScore < 1 { signals.append("grounding:weak") }

        let composite = ocrScore * 0.25 + semanticScore * 0.35 + validationScore * 0.2 + groundingScore * 0.2
        let requiresManual = composite < manualConfirmationThreshold
            || suggestion.mappingSource == .estimated
            || suggestion.isLowConfidence

        return Breakdown(
            ocrScore: ocrScore,
            semanticScore: semanticScore,
            validationScore: validationScore,
            groundingScore: groundingScore,
            compositeScore: composite,
            requiresManualConfirmation: requiresManual,
            signals: signals
        )
    }

    static func enrich(
        _ suggestions: [OcrFieldSuggestion],
        documentType: ScannedDocumentType,
        ocrCorpus: String,
        averageOCRBlockConfidence: Double
    ) -> [OcrFieldSuggestion] {
        suggestions.map { suggestion in
            let breakdown = score(
                suggestion: suggestion,
                documentType: documentType,
                ocrCorpus: ocrCorpus,
                averageOCRBlockConfidence: averageOCRBlockConfidence
            )
            let label = confidenceLabel(for: breakdown.compositeScore)
            return OcrFieldSuggestion(
                profileKey: suggestion.profileKey,
                label: suggestion.label,
                value: suggestion.value,
                confidence: label,
                confidenceScore: breakdown.compositeScore,
                mappingSource: suggestion.mappingSource,
                confidenceBreakdown: breakdown
            )
        }
    }

    private static func semanticScoreFor(source: FieldMappingSource?, base: Double) -> Double {
        switch source {
        case .barcode, .mrz: return 0.96
        case .template: return min(0.93, max(base, 0.86))
        case .learned: return min(0.88, max(base, 0.8))
        case .onDevice: return min(0.9, max(base, 0.78))
        case .networkLLM: return min(0.92, max(base, 0.8))
        case .estimated: return min(0.58, base)
        case nil: return base
        }
    }

    private static func confidenceLabel(for score: Double) -> String {
        if score >= 0.85 { return "High" }
        if score >= manualConfirmationThreshold { return "Medium" }
        return "Estimated"
    }

    private static func normalize(corpus: String) -> String {
        corpus.lowercased()
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "|", with: " ")
    }
}
