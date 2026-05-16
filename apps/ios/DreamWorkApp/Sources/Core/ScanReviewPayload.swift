import Foundation

struct ScanReviewPayload: Identifiable {
    let id = UUID()
    /// Document type chosen before capture/import.
    let userDocumentType: ScannedDocumentType
    let fullText: String
    let ocrBlockCount: Int
    let pageCount: Int
    let suggestions: [OcrFieldSuggestion]
    let understanding: DocumentUnderstandingResult?
    let personResolution: PersonResolutionSuggestion?
    let storagePlan: StoragePlanSuggestion?
    /// Pre-filled profile from DL barcode/OCR/GenAI when creating a new household member.
    let prefilledPerson: PersonRecord?

    var documentType: ScannedDocumentType { userDocumentType }
}
