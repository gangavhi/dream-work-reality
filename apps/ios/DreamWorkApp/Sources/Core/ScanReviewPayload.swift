import Foundation

struct ScanReviewPayload: Identifiable {
    let id = UUID()
    /// UI category (mapped from model open vocabulary when available).
    let detectedDocumentType: ScannedDocumentType
    /// Human-readable type from on-device extraction (e.g. "School Enrollment Form").
    let openDocumentTypeLabel: String
    let classificationConfidence: Double
    let classificationSignals: [String]
    let fullText: String
    let ocrBlockCount: Int
    let pageCount: Int
    let suggestions: [OcrFieldSuggestion]
    let understanding: DocumentUnderstandingResult?
    let personResolution: PersonResolutionSuggestion?
    let storagePlan: StoragePlanSuggestion?
    let usedAI: Bool
    /// Shown when network LLM failed or fields are regex-only estimates.
    let mappingNotice: String?
    let usedMachineReadablePayload: Bool
    let usedHeuristicFallback: Bool
    let identityGraph: StructuredIdentityGraph
    let autofillPayload: SmartAutofillPayload
    let pipelineTrace: [String]
    /// Numbered OCR blocks (same format fed to on-device models).
    let ocrModelInput: String
    /// Label→value pairs detected from layout (input to field mapping).
    let ocrLabelValuePairs: String
    /// Standardized schema output (document-type-specific JSON fields + confidence).
    let standardizedOutput: SchemaMappingEngine.StandardizedDocumentOutput?
    let fieldsRequiringReview: [String]
    /// Pre-filled profile from DL barcode/OCR/GenAI when creating a new household member.
    let prefilledPerson: PersonRecord?
    /// When false, automatic extraction already ran; no extra tap required.
    let showManualExtractionRetry: Bool

    var documentType: ScannedDocumentType { detectedDocumentType }
}
