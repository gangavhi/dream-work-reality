import Foundation

/// Configures on-device and local-network LLM endpoints for document field extraction.
/// Default: fully on-device via Rust core (zero egress).
enum GenAISettings {
    enum Provider: String, Identifiable {
        case onDevice
        case off
        case localLLM = "ollama"
        case cloudLLMDevOnly = "openAI"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .onDevice:
                return "On-device (built-in, no network)"
            case .off:
                return "Off (OCR + heuristics only)"
            case .localLLM:
                return "Local network LLM (Ollama / LM Studio)"
            case .cloudLLMDevOnly:
                return "Cloud LLM (DEBUG — data leaves device)"
            }
        }

        static var allCases: [Provider] {
            #if DEBUG
            [.onDevice, .off, .localLLM, .cloudLLMDevOnly]
            #else
            [.onDevice, .off, .localLLM]
            #endif
        }
    }

    private static let providerKey = "dreamwork.genai.provider"
    private static let baseURLKey = "dreamwork.genai.base_url"
    private static let modelKey = "dreamwork.genai.model"

    static var provider: Provider {
        get {
            guard let raw = UserDefaults.standard.string(forKey: providerKey) else {
                return .onDevice
            }
            // Migrate legacy default keys.
            if raw == "Off (layout + universal heuristics)" || raw == "off_legacy" {
                return .onDevice
            }
            guard let value = Provider(rawValue: raw) else { return .onDevice }
            return ZeroEgressPolicy.sanitizedProvider(value)
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: providerKey) }
    }

    static var baseURL: String {
        get {
            if let saved = UserDefaults.standard.string(forKey: baseURLKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !saved.isEmpty
            {
                return saved
            }
            switch provider {
            case .localLLM: return "http://127.0.0.1:11434/v1"
            case .cloudLLMDevOnly: return "https://api.openai.com/v1"
            case .onDevice, .off: return ""
            }
        }
        set { UserDefaults.standard.set(newValue, forKey: baseURLKey) }
    }

    static var model: String {
        get {
            if let saved = UserDefaults.standard.string(forKey: modelKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !saved.isEmpty
            {
                return saved
            }
            switch provider {
            case .localLLM: return "llama3.2"
            case .cloudLLMDevOnly: return "gpt-4o-mini"
            case .onDevice, .off: return ""
            }
        }
        set { UserDefaults.standard.set(newValue, forKey: modelKey) }
    }

    /// Returns credentials when local-network LLM enrichment should run (never for `.onDevice`).
    static var activeLLMConfig: (baseURL: String, model: String, apiKey: String)? {
        switch provider {
        case .onDevice, .off:
            return nil
        case .localLLM:
            let url = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !url.isEmpty, ZeroEgressPolicy.allowsLLMEndpoint(url) else { return nil }
            return (url, model, "ollama")
        case .cloudLLMDevOnly:
            #if DEBUG
            guard ZeroEgressPolicy.isCloudLLMDevEnabled else { return nil }
            guard let key = DevAPIKeyStore.openAIAPIKey else { return nil }
            let url = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !url.isEmpty, ZeroEgressPolicy.allowsLLMEndpoint(url) else { return nil }
            return (url, model, key)
            #else
            return nil
            #endif
        }
    }
}
