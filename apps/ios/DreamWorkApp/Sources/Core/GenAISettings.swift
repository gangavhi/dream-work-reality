import Foundation

/// On-device document field extraction only — no remote or network LLM endpoints.
enum GenAISettings {
    enum Provider: String, Identifiable {
        case onDevice
        case off

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .onDevice:
                return "On-device (built-in, no network)"
            case .off:
                return "Off (OCR + heuristics only)"
            }
        }

        static var allCases: [Provider] { [.onDevice, .off] }
    }

    private static let providerKey = "dreamwork.genai.provider"

    static var provider: Provider {
        get {
            guard let raw = UserDefaults.standard.string(forKey: providerKey) else {
                return .onDevice
            }
            if raw == "Off (layout + universal heuristics)" || raw == "off_legacy" {
                return .onDevice
            }
            // Legacy network providers — migrated to on-device (zero egress).
            if raw == ProviderLegacy.localLLM || raw == ProviderLegacy.cloudLLM {
                return .onDevice
            }
            guard let value = Provider(rawValue: raw) else { return .onDevice }
            return value
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: providerKey) }
    }

    /// Network LLM extraction is disabled — document OCR never leaves this device over the internet.
    static var activeLLMConfig: (baseURL: String, model: String, apiKey: String)? {
        nil
    }

    /// Legacy persisted raw values (migration only).
    private enum ProviderLegacy {
        static let localLLM = "ollama"
        static let cloudLLM = "openAI"
    }
}
