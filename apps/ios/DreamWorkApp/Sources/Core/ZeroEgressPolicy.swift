import Foundation

/// Enforces [trustnest-zero-egress-design-constraint.md]: household PII and OCR text must not
/// cross the public internet during normal product use.
enum ZeroEgressPolicy {
    private static let coreAPISyncKey = "dreamwork.zero_egress.core_api_sync"

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

    /// Document OCR / PII must not be sent to any HTTP LLM endpoint (internet or LAN).
    static func allowsLLMEndpoint(_ baseURL: String) -> Bool {
        _ = baseURL
        return false
    }

    /// Whether a URL may receive PII for developer `core-api` demo sync (localhost only).
    static func allowsCoreAPILocalhost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return isLoopbackHost(host)
    }

    /// Sanitize persisted LLM provider after policy changes.
    static func sanitizedProvider(_ raw: GenAISettings.Provider) -> GenAISettings.Provider {
        raw
    }

    // MARK: - Host classification

    private static func isLoopbackHost(_ host: String) -> Bool {
        host == "localhost" || host == "127.0.0.1" || host == "::1" || host == "[::1]"
    }
}
