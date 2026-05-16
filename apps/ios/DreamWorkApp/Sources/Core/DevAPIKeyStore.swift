import Foundation

/// Dev-only OpenAI API key for Stage 1 (`/ingest/understand`). Production builds should leave this empty.
enum DevAPIKeyStore {
    private static let userDefaultsKey = "dreamwork.dev.openai_api_key"

    static var openAIAPIKey: String? {
        if let fromSettings = UserDefaults.standard.string(forKey: userDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !fromSettings.isEmpty
        {
            return fromSettings
        }
        for name in ["DREAMWORK_OPENAI_API_KEY", "OPENAI_API_KEY"] {
            if let value = ProcessInfo.processInfo.environment[name]?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !value.isEmpty
            {
                return value
            }
        }
        return nil
    }

    static func saveOpenAIAPIKey(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        } else {
            UserDefaults.standard.set(trimmed, forKey: userDefaultsKey)
        }
    }
}
