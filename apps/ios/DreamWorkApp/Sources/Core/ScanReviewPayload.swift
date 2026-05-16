import Foundation

struct ScanReviewPayload: Identifiable {
    let id = UUID()
    let documentType: ScannedDocumentType
    let fullText: String
    let ocrBlockCount: Int
    let pageCount: Int
    let suggestions: [OcrFieldSuggestion]
}
