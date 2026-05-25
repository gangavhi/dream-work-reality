import Foundation

enum FieldMappingSource: String, Hashable {
    case barcode
    case mrz
    case template
    case learned
    case onDevice
    case networkLLM
    case estimated

    var displayLabel: String {
        switch self {
        case .barcode: return "Barcode"
        case .mrz: return "MRZ"
        case .template: return "Template"
        case .learned: return "Learned"
        case .onDevice: return "On-device"
        case .networkLLM: return "Network model"
        case .estimated: return "Estimated"
        }
    }
}

struct OcrFieldSuggestion: Identifiable, Hashable {
    let profileKey: String
    let label: String
    let value: String
    let confidence: String
    let confidenceScore: Double
    let mappingSource: FieldMappingSource?
    let confidenceBreakdown: ConfidenceOrchestrator.Breakdown?

    var id: String { profileKey }

    init(
        profileKey: String,
        label: String,
        value: String,
        confidence: String,
        confidenceScore: Double? = nil,
        mappingSource: FieldMappingSource? = nil,
        confidenceBreakdown: ConfidenceOrchestrator.Breakdown? = nil
    ) {
        self.profileKey = profileKey
        self.label = label
        self.value = value
        self.confidence = confidence
        self.confidenceScore = confidenceScore ?? Self.score(from: confidence)
        self.mappingSource = mappingSource
        self.confidenceBreakdown = confidenceBreakdown
    }

    static func score(from confidence: String) -> Double {
        switch confidence {
        case "High": return 0.9
        case "Medium": return 0.72
        case "Estimated": return 0.52
        default: return 0.45
        }
    }

    var isHighConfidence: Bool { confidenceScore >= 0.85 }
    var isLowConfidence: Bool { confidenceScore < 0.65 }

    func withMappingSource(_ source: FieldMappingSource) -> OcrFieldSuggestion {
        OcrFieldSuggestion(
            profileKey: profileKey,
            label: label,
            value: value,
            confidence: confidence,
            confidenceScore: confidenceScore,
            mappingSource: source,
            confidenceBreakdown: confidenceBreakdown
        )
    }

    var requiresManualConfirmation: Bool {
        confidenceBreakdown?.requiresManualConfirmation ?? isLowConfidence
    }
}
