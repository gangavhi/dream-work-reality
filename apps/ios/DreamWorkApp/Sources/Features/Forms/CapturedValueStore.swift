import Foundation

/// Local-only store used to avoid re-capturing the same identity values across scans.
/// It is intentionally simple: normalize values and remember the last captured value per key.
struct CapturedValueStore {
    private let storageKey = "captured_values.v1"

    private func load() -> [String: String] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return dict
    }

    private func save(_ dict: [String: String]) {
        guard let data = try? JSONEncoder().encode(dict) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    func normalized(key: String, value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }

        switch key {
        case "first_name", "last_name", "display_name", "city", "state":
            return trimmed
                .replacingOccurrences(of: #"[\s]+"#, with: " ", options: .regularExpression)
                .uppercased()
        case "address_line_1":
            return trimmed
                .replacingOccurrences(of: #"[\s]+"#, with: " ", options: .regularExpression)
                .uppercased()
        case "postal_code":
            return trimmed
                .replacingOccurrences(of: #"[^0-9]"#, with: "", options: .regularExpression)
        case "date_of_birth":
            // Expect MM/dd/yyyy; keep digits only so equivalent formats match.
            return trimmed
                .replacingOccurrences(of: #"[^0-9]"#, with: "", options: .regularExpression)
        default:
            return trimmed
                .replacingOccurrences(of: #"[\s]+"#, with: " ", options: .regularExpression)
        }
    }

    func hasSameCapturedValue(key: String, candidate: String) -> Bool {
        let dict = load()
        let cand = normalized(key: key, value: candidate)
        guard !cand.isEmpty else { return true }
        guard let existing = dict[key] else { return false }
        return existing == cand
    }

    mutating func captureIfNew(key: String, value: String) -> Bool {
        let cand = normalized(key: key, value: value)
        guard !cand.isEmpty else { return false }
        var dict = load()
        if dict[key] == cand { return false }
        dict[key] = cand
        save(dict)
        return true
    }
}

