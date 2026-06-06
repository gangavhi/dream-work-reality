import Foundation
import NaturalLanguage

/// Document type using Vision hints, NaturalLanguage, and optional Create ML text classifier.
enum NLDocumentClassifier {
    struct Result: Hashable {
        let displayType: ScannedDocumentType
        let openLabel: String
        let confidence: Double
        let engineID: String
    }

    static func classify(
        layoutText: String,
        payloadHints: EmbeddedPayloadHints.Result
    ) -> Result {
        if !payloadHints.mrzLines.isEmpty {
            return Result(
                displayType: .passport,
                openLabel: "passport",
                confidence: 0.94,
                engineID: "nl:mrz"
            )
        }
        if payloadHints.barcodePayloads.contains(where: { $0.contains("ANSI ") || $0.contains("DAA") }) {
            return Result(
                displayType: .driversLicense,
                openLabel: "drivers_license",
                confidence: 0.95,
                engineID: "nl:barcode_aamva"
            )
        }

        let keyword = DocumentTypeClassifier.classify(from: layoutText)
        if keyword.matchedSignals.contains(where: { $0 == "birth certificate" || $0 == "marriage certificate" }) {
            let openLabel = DocumentTypeClassifier.mapToUnderstandingType(keyword.documentType)
            return Result(
                displayType: keyword.documentType,
                openLabel: openLabel,
                confidence: keyword.confidence,
                engineID: "nl:keywords"
            )
        }

        if let createML = classifyWithCreateML(layoutText: layoutText) {
            return createML
        }

        let heuristic = keyword
        let openLabel = DocumentTypeClassifier.mapToUnderstandingType(heuristic.documentType)
        return Result(
            displayType: heuristic.documentType,
            openLabel: openLabel,
            confidence: heuristic.confidence,
            engineID: "nl:keywords"
        )
    }

    private static func classifyWithCreateML(layoutText: String) -> Result? {
        guard let model = CreateMLModelRegistry.documentTypeClassifier else { return nil }
        let sample = String(layoutText.prefix(4000))
        guard !sample.isEmpty,
              let label = model.predictedLabel(for: sample)
        else { return nil }
        let presentation = DocumentTypePresentation.resolve(label)
        return Result(
            displayType: presentation.enumType,
            openLabel: label,
            confidence: 0.88,
            engineID: "createml:text_classifier"
        )
    }
}
