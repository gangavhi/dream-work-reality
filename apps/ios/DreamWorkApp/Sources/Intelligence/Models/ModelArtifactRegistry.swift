import Foundation

/// On-device model slots — Apple frameworks are active by default; optional Create ML / Rust artifacts when present.
enum ModelArtifactSlot: String, CaseIterable, Identifiable {
    case visionOCR = "vision.en.v1"
    case documentClassifier = "document.classifier.v1"
    case fieldEmbedder = "embed.nl.v1"
    case storagePlanner = "sql.storage.planner.v1"
    case layoutLM = "layoutlmv3.v1"
    case fraudDetector = "fraud.doc.v1"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .visionOCR: return "Apple Vision OCR"
        case .documentClassifier: return "Create ML document classifier"
        case .fieldEmbedder: return "NaturalLanguage embeddings"
        case .storagePlanner: return "Apple storage planner"
        case .layoutLM: return "LayoutLMv3 (optional)"
        case .fraudDetector: return "Fraud detector (optional)"
        }
    }

    var runtimeKind: ModelRuntimeKind {
        switch self {
        case .visionOCR, .fieldEmbedder, .storagePlanner:
            return .appleVision
        case .documentClassifier, .layoutLM, .fraudDetector:
            return .coreML
        }
    }
}

enum ModelRuntimeKind: String {
    case appleVision
    case coreML
    case heuristicFallback
}

enum ModelLoadState: Equatable {
    case notInstalled
    case installed(path: String)
    case active
    case heuristicFallback
}

enum ModelArtifactRegistry {
    static func loadState(for slot: ModelArtifactSlot) -> ModelLoadState {
        switch slot {
        case .visionOCR, .fieldEmbedder, .storagePlanner:
            return .active
        case .documentClassifier:
            if CreateMLModelRegistry.hasBundledClassifier,
               let path = CreateMLModelRegistry.documentClassifierPath()
            {
                return .installed(path: path)
            }
            return .notInstalled
        case .layoutLM, .fraudDetector:
            if let path = bundledCoreMLPath(for: slot) {
                return .installed(path: path)
            }
            return .notInstalled
        }
    }

    static func activeRuntimeKind(for slot: ModelArtifactSlot) -> ModelRuntimeKind {
        switch loadState(for: slot) {
        case .active, .installed:
            return slot.runtimeKind
        case .heuristicFallback:
            return .heuristicFallback
        case .notInstalled:
            return slot == .visionOCR || slot == .fieldEmbedder || slot == .storagePlanner
                ? .appleVision
                : .heuristicFallback
        }
    }

    static func statusSummary() -> String {
        ModelArtifactSlot.allCases.map { slot in
            let label: String = {
                switch loadState(for: slot) {
                case .active: return "active"
                case .installed: return "installed"
                case .heuristicFallback: return "fallback"
                case .notInstalled: return "not installed"
                }
            }()
            return "\(slot.displayName): \(label)"
        }.joined(separator: " · ")
    }

    private static func bundledCoreMLPath(for slot: ModelArtifactSlot) -> String? {
        if let installed = BundledModelStore.artifactPath(artifactID: slot.rawValue) {
            return installed
        }

        let name: String = {
            switch slot {
            case .layoutLM: return "layoutlmv3"
            case .fraudDetector: return "fraud_doc"
            default: return ""
            }
        }()
        guard !name.isEmpty,
              let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc")
        else { return nil }
        return url.path
    }
}
