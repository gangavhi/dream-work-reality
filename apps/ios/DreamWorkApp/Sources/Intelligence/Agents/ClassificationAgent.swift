import Foundation

/// Shared classification result type for the intelligence orchestrator (no GGUF).
enum ClassificationAgent {
    struct Result: Hashable {
        let openDocumentType: String?
        let displayLabel: String
        let enumType: ScannedDocumentType
        let confidence: Double
        let engineID: String
        let issuerRegion: String?
        let country: String?
        let runtimeStatus: String
    }

    static func pendingParserClassification() -> Result {
        Result(
            openDocumentType: nil,
            displayLabel: "Document",
            enumType: .other,
            confidence: 0,
            engineID: "apple_native",
            issuerRegion: nil,
            country: nil,
            runtimeStatus: "classifier_pending_extraction"
        )
    }

    static func failed(status: String) -> Result {
        Result(
            openDocumentType: "other",
            displayLabel: "Document",
            enumType: .other,
            confidence: 0,
            engineID: "apple_native",
            issuerRegion: nil,
            country: nil,
            runtimeStatus: status
        )
    }
}
