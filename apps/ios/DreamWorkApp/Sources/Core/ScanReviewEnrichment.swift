import Foundation

enum PersonResolutionKind: String, Codable {
    case matchExisting = "match_existing"
    case newPerson = "new_person"
    case ambiguous
}

struct PersonResolutionCandidate: Identifiable, Hashable {
    let personID: String
    let score: Double
    let reasons: [String]

    var id: String { personID }

    var reasonSummary: String {
        reasons.joined(separator: ", ")
    }
}

struct PersonResolutionSuggestion: Hashable {
    let resolution: PersonResolutionKind
    let personID: String?
    let confidence: Double
    let candidates: [PersonResolutionCandidate]
}

struct DocumentUnderstandingResult: Hashable {
    let documentType: String
    let documentTypeConfidence: Double
    let issuerRegion: String?
    let displayNameHint: String?
    let usedAI: Bool
}

struct ScanReviewEnrichment: Hashable {
    let understanding: DocumentUnderstandingResult?
    let personResolution: PersonResolutionSuggestion?
    let storagePlan: StoragePlanSuggestion?
    let suggestions: [OcrFieldSuggestion]
    let usedAI: Bool
}
