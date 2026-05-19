import Foundation

struct ScanReviewPayload: Identifiable {
    let id = UUID()
    /// Auto-detected document type from OCR heuristics and/or Document AI.
    let detectedDocumentType: ScannedDocumentType
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
