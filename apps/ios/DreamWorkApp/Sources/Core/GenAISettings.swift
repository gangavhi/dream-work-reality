import Foundation

/// Optional network LLM override. Default path is Apple Vision + NaturalLanguage (no egress).
enum GenAISettings {
    enum Provider: String, CaseIterable, Identifiable {
        case appleNative = "Apple Vision + NaturalLanguage (recommended)"
        case off = "Apple native only (same as recommended)"
        case ollama = "Optional: Ollama / network LLM"
        case openAI = "Optional: Cloud LLM (dev — data leaves device)"

        var id: String { rawValue }
    }

    private static let providerKey = "dreamwork.genai.provider"
    private static let baseURLKey = "dreamwork.genai.base_url"
    private static let modelKey = "dreamwork.genai.model"

    private static let legacyOnDeviceLabels = [
        "On-device GGUF",
        "On-device (GGUF)",
    ]

    static var provider: Provider {
        get {
            guard let raw = UserDefaults.standard.string(forKey: providerKey) else {
                return .appleNative
            }
            if legacyOnDeviceLabels.contains(raw) {
                return .appleNative
            }
            return Provider(rawValue: raw) ?? .appleNative
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: providerKey) }
    }

    static var usesAppleNativeStack: Bool {
        switch provider {
        case .appleNative, .off:
            return true
        case .ollama, .openAI:
            return false
        }
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
            case .ollama: return "http://127.0.0.1:11434/v1"
            case .openAI: return "https://api.openai.com/v1"
            case .appleNative, .off: return ""
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
            case .ollama: return "llama3.2"
            case .openAI: return "gpt-4o-mini"
            case .appleNative, .off: return ""
            }
        }
        set { UserDefaults.standard.set(newValue, forKey: modelKey) }
    }

    /// True when Settings enable an optional network LLM on top of Apple-native extraction.
    static var shouldUseOptionalNetworkLLM: Bool {
        switch provider {
        case .appleNative, .off:
            return false
        case .ollama, .openAI:
            return activeLLMConfig != nil
        }
    }

    /// Returns credentials when optional network LLM enrichment should run.
    static var activeLLMConfig: (baseURL: String, model: String, apiKey: String)? {
        switch provider {
        case .appleNative, .off:
            return nil
        case .ollama:
            let url = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !url.isEmpty else { return nil }
            return (url, model, "ollama")
        case .openAI:
            guard let key = DevAPIKeyStore.openAIAPIKey else { return nil }
            let url = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !url.isEmpty else { return nil }
            return (url, model, key)
        }
    }
}
