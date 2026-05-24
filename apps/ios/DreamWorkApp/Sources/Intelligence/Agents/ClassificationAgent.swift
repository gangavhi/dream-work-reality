import Foundation

/// Document type classification — Rust/heuristic today; Phi-3 / Qwen CoreML or GGUF when loaded.
enum ClassificationAgent {
    struct Result: Hashable {
        let openDocumentType: String?
        let displayLabel: String
        let enumType: ScannedDocumentType
        let confidence: Double
        let engineID: String
        let issuerRegion: String?
        let country: String?
    }

    static func classify(
        modelInput: String,
        mappedDocumentType: String?,
        machineReadableSources: [String]
    ) -> Result {
        var openType = mappedDocumentType
        if openType == nil, machineReadableSources.contains("pdf417")
            || machineReadableSources.contains("drivers_license")
        {
            openType = "drivers_license"
        } else if openType == nil, machineReadableSources.contains("passport") {
            openType = "passport"
        }
        if openType == nil {
            openType = ProfileSchemaKeysForDocument.inferOpenType(from: modelInput)
            if openType == "other" { openType = nil }
        }

        let engineID: String = {
            switch ModelArtifactRegistry.loadState(for: .documentClassifier) {
            case .installed: return ModelArtifactSlot.documentClassifier.rawValue
            case .heuristicFallback: return "heuristic.on_device.v1"
            default: return "heuristic.on_device.v1"
            }
        }()

        let presentation = DocumentTypePresentation.resolve(openType)
        let confidence: Double = {
            if !machineReadableSources.isEmpty { return 0.94 }
            if engineID.contains("heuristic") { return 0.78 }
            return 0.88
        }()

        return Result(
            openDocumentType: openType,
            displayLabel: openType.map { DocumentTypePresentation.resolve($0).displayLabel } ?? presentation.displayLabel,
            enumType: machineReadableSources.contains("pdf417") ? .driversLicense : presentation.enumType,
            confidence: confidence,
            engineID: engineID,
            issuerRegion: nil,
            country: nil
        )
    }
}
