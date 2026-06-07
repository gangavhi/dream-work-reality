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
    let displayDocumentType: ScannedDocumentType
    let openDocumentTypeLabel: String
    let plainText: String
    let mappingNotice: String?
    let usedMachineReadablePayload: Bool
    let usedHeuristicFallback: Bool
    let identityGraph: StructuredIdentityGraph
    let autofillPayload: SmartAutofillPayload
    let pipelineTrace: [String]
    /// Numbered OCR blocks (same format fed to on-device models).
    let ocrModelInput: String
    /// Label→value pairs detected from layout (input to field mapping).
    let ocrLabelValuePairs: String
    let standardizedOutput: SchemaMappingEngine.StandardizedDocumentOutput?
    let fieldsRequiringReview: [String]
    /// True when Qwen GGUF was skipped (memory/policy) but user may retry manually.
    let heavyLLMDeferred: Bool
    /// True when the scan ran the full on-device pipeline including GGUF when allowed.
    let ranFullOnDevicePipeline: Bool
    /// Canonical document type for stash whitelist (rewrite v2).
    let canonicalDocumentType: String
    /// Staged file pending encrypted stash on profile save.
    let sourceFileURL: URL?
}
