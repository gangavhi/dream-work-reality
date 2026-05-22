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
    /// Pre-filled profile from DL barcode/OCR/GenAI when creating a new household member.
    let prefilledPerson: PersonRecord?

    var documentType: ScannedDocumentType { detectedDocumentType }
}
