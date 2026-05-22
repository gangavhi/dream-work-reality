import Foundation

/// Enforces [trustnest-zero-egress-design-constraint.md]: household PII and OCR text must not
/// cross the public internet during normal product use. Local loopback and private LAN endpoints
/// (e.g. Ollama on a Mac) are permitted for on-network inference.
enum ZeroEgressPolicy {
    private static let cloudLLMDevKey = "dreamwork.zero_egress.allow_cloud_llm_dev"
    private static let coreAPISyncKey = "dreamwork.zero_egress.core_api_sync"

    /// DEBUG-only explicit opt-in for cloud LLM providers (OpenAI, etc.). Always false in Release.
    static var isCloudLLMDevEnabled: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: cloudLLMDevKey)
        #else
        return false
        #endif
    }

    #if DEBUG
    static func setCloudLLMDevEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: cloudLLMDevKey)
    }
    #endif

    /// DEBUG-only sync to localhost `core-api` for extension demo. Disabled in Release.
    static var isDeveloperCoreAPISyncEnabled: Bool {
        #if DEBUG
        if UserDefaults.standard.object(forKey: coreAPISyncKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: coreAPISyncKey)
        #else
        return false
        #endif
    }

    #if DEBUG
    static func setDeveloperCoreAPISyncEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: coreAPISyncKey)
    }
    #endif

    /// Whether an OpenAI-compatible LLM base URL may receive OCR-bearing prompts.
    static func allowsLLMEndpoint(_ baseURL: String) -> Bool {
        guard let host = normalizedHost(from: baseURL) else { return false }
        if isLoopbackHost(host) || isPrivateNetworkHost(host) || host.hasSuffix(".local") {
            return true
        }
        #if DEBUG
        if isCloudLLMDevEnabled, isKnownCloudDevHost(host) {
            return true
        }
        #endif
        return false
    }

    /// Whether a URL may receive PII for developer `core-api` demo sync (localhost only).
    static func allowsCoreAPILocalhost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return isLoopbackHost(host)
    }

    /// Sanitize persisted LLM provider after policy changes or retail build constraints.
    static func sanitizedProvider(_ raw: GenAISettings.Provider) -> GenAISettings.Provider {
        switch raw {
        case .onDevice, .off, .localLLM:
            return raw
        case .cloudLLMDevOnly:
            #if DEBUG
            return isCloudLLMDevEnabled ? .cloudLLMDevOnly : .off
            #else
            return .off
            #endif
        }
    }

    // MARK: - Host classification

    private static func normalizedHost(from baseURL: String) -> String? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "http://\(trimmed)"
        guard let url = URL(string: withScheme), let host = url.host?.lowercased(), !host.isEmpty else {
            return nil
        }
        return host
    }

    private static func isLoopbackHost(_ host: String) -> Bool {
        host == "localhost" || host == "127.0.0.1" || host == "::1" || host == "[::1]"
    }

    private static func isPrivateNetworkHost(_ host: String) -> Bool {
        if host.contains(":") {
            return host.hasPrefix("fe80:") || host.hasPrefix("fc") || host.hasPrefix("fd")
        }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false).compactMap { Int($0) }
        guard parts.count == 4, parts.allSatisfy({ (0 ... 255).contains($0) }) else { return false }
        switch parts[0] {
        case 10:
            return true
        case 172:
            return (16 ... 31).contains(parts[1])
        case 192:
            return parts[1] == 168
        default:
            return false
        }
    }

    #if DEBUG
    private static func isKnownCloudDevHost(_ host: String) -> Bool {
        let known: Set<String> = [
            "api.openai.com",
            "openai.com",
        ]
        if known.contains(host) { return true }
        return host.hasSuffix(".openai.azure.com")
    }
    #endif
}
