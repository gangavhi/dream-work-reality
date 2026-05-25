import Foundation

/// Standalone on-device model slots (lazy-loaded). Each slot maps to one artifact family per ADR 0017.
enum ModelArtifactSlot: String, CaseIterable, Identifiable {
    case visionOCR = "vision.en.v1"
    case paddleOCR = "paddle.ocr.v1"
    case layoutLM = "layoutlmv3.v1"
    case documentClassifier = "document.classifier.v1"
    case nerDistilBERT = "ner.distilbert.v1"
    case fieldEmbedder = "embed.minilm.v1"
    case generativeLLM = "llm.schema.standard.v1"
    case storagePlanner = "sql.storage.planner.v1"
    case fraudDetector = "fraud.doc.v1"
    case visionLanguage = "vlm.qwen2vl.v1"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .visionOCR: return "Apple Vision OCR"
        case .paddleOCR: return "PaddleOCR"
        case .layoutLM: return "LayoutLMv3"
        case .documentClassifier: return "Document classifier (Qwen2.5)"
        case .nerDistilBERT: return "DistilBERT NER"
        case .fieldEmbedder: return "MiniLM field embedder"
        case .generativeLLM: return "Generative LLM"
        case .storagePlanner: return "Storage planner (SQL SLM)"
        case .fraudDetector: return "Fraud detector"
        case .visionLanguage: return "Vision-language model"
        }
    }

    var runtimeKind: ModelRuntimeKind {
        switch self {
        case .visionOCR: return .appleVision
        case .paddleOCR, .layoutLM, .nerDistilBERT, .fieldEmbedder, .fraudDetector:
            return .coreML
        case .documentClassifier, .generativeLLM, .storagePlanner, .visionLanguage:
            return .ggufMetal
        }
    }
}

enum ModelRuntimeKind: String {
    case appleVision
    case coreML
    case ggufMetal
    case heuristicFallback
}

enum ModelLoadState: Equatable {
    case notInstalled
    case installed(path: String)
    case active
    case heuristicFallback
}

/// Registry of standalone models — tracks install state; loads lazily when artifacts appear on disk.
enum ModelArtifactRegistry {
    static func loadState(for slot: ModelArtifactSlot) -> ModelLoadState {
        switch slot {
        case .visionOCR:
            return .active
        case .documentClassifier:
            if let path = BundledModelStore.documentClassifierArtifactPath() {
                return .installed(path: path)
            }
            return .notInstalled
        case .generativeLLM:
            if let path = BundledModelStore.liteArtifactPath() {
                return .installed(path: path)
            }
            return .notInstalled
        case .storagePlanner:
            if let path = BundledModelStore.storagePlannerArtifactPath() {
                return .installed(path: path)
            }
            return .notInstalled
        case .fieldEmbedder, .nerDistilBERT, .layoutLM, .paddleOCR, .fraudDetector, .visionLanguage:
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
            return slot == .visionOCR ? .appleVision : .heuristicFallback
        }
    }

    static func statusSummary() -> String {
        ModelArtifactSlot.allCases.map { slot in
            let label: String = {
                switch loadState(for: slot) {
                case .active: return "active"
                case .installed: return "installed"
            case .heuristicFallback: return "fallback disabled"
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
            case .paddleOCR: return "paddle_ocr"
            case .layoutLM: return "layoutlmv3"
            case .nerDistilBERT: return "distilbert_ner"
            case .fieldEmbedder: return "minilm_field_embed"
            case .fraudDetector: return "fraud_doc"
            case .visionLanguage: return "qwen2_vl"
            default: return ""
            }
        }()
        guard !name.isEmpty,
              let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc")
        else { return nil }
        return url.path
    }
}
