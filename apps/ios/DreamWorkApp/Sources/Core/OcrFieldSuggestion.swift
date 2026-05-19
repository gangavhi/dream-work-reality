import Foundation

struct OcrFieldSuggestion: Identifiable, Hashable {
    let profileKey: String
    let label: String
    let value: String
    let confidence: String
    let confidenceScore: Double

    var id: String { profileKey }

    init(
        profileKey: String,
        label: String,
        value: String,
        confidence: String,
        confidenceScore: Double? = nil
    ) {
        self.profileKey = profileKey
        self.label = label
        self.value = value
        self.confidence = confidence
        self.confidenceScore = confidenceScore ?? Self.score(from: confidence)
    }

    static func score(from confidence: String) -> Double {
        switch confidence {
        case "High": return 0.9
        case "Medium": return 0.72
        default: return 0.45
        }
    }

    var isHighConfidence: Bool { confidenceScore >= 0.85 }
    var isLowConfidence: Bool { confidenceScore < 0.65 }
}
