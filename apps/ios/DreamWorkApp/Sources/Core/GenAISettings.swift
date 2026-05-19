import Foundation

/// Configures OpenAI-compatible LLM endpoints (OpenAI cloud, Ollama, LM Studio, etc.).
enum GenAISettings {
    enum Provider: String, CaseIterable, Identifiable {
        case off = "Off (heuristics only)"
        case ollama = "Ollama / local LLM"
        case openAI = "OpenAI-compatible cloud"

        var id: String { rawValue }
    }

    private static let providerKey = "dreamwork.genai.provider"
    private static let baseURLKey = "dreamwork.genai.base_url"
    private static let modelKey = "dreamwork.genai.model"

    static var provider: Provider {
        get {
            guard let raw = UserDefaults.standard.string(forKey: providerKey),
                  let value = Provider(rawValue: raw)
            else { return .openAI }
            return value
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
            case .ollama: return "http://127.0.0.1:11434/v1"
            case .openAI: return "https://api.openai.com/v1"
            case .off: return ""
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
            case .off: return ""
            }
        }
        set { UserDefaults.standard.set(newValue, forKey: modelKey) }
    }

    /// Returns credentials when LLM enrichment should run.
    static var activeLLMConfig: (baseURL: String, model: String, apiKey: String)? {
        switch provider {
        case .off:
            return nil
        case .ollama:
            let url = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !url.isEmpty else { return nil }
            // Ollama accepts any non-empty bearer token.
            return (url, model, "ollama")
        case .openAI:
            guard let key = DevAPIKeyStore.openAIAPIKey else { return nil }
            let url = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !url.isEmpty else { return nil }
            return (url, model, key)
        }
    }
}
