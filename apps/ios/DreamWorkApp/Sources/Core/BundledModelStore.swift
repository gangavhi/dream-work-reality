import Foundation

/// Locates optional on-device GGUF weights under Application Support (user-approved download or sideload).
enum BundledModelStore {
    struct Manifest: Decodable {
        struct Artifact: Decodable {
            let artifact_id: String
            let filename: String
            let description: String
            let bytes_approx: Int?
            let sha256: String?
            let download_url: String?
        }

        let version: Int
        let artifacts: [Artifact]
    }

    static var modelsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base
            .appendingPathComponent("DreamWork", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
    }

    static func manifest() -> Manifest? {
        guard let url = Bundle.main.url(forResource: "model-manifest", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(Manifest.self, from: data)
    }

    static func liteArtifactPath() -> String? {
        guard let manifest = manifest(),
              let artifact = manifest.artifacts.first(where: { $0.artifact_id == "llm.schema.lite.v1" })
        else { return nil }
        let path = modelsDirectory.appendingPathComponent(artifact.filename).path
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    static func installStatusMessage() -> String {
        if liteArtifactPath() != nil {
            return "On-device model installed at llm.schema.lite.v1. Heuristic extraction runs today; full GGUF inference ships in a future update."
        }
        if let artifact = manifest()?.artifacts.first(where: { $0.artifact_id == "llm.schema.lite.v1" }) {
            let gb = Double(artifact.bytes_approx ?? 0) / 1_000_000_000.0
            return String(format: "Optional model %@ (~%.1f GB) not installed. Extraction uses built-in on-device heuristics (zero egress).", artifact.filename, gb)
        }
        return "Built-in on-device extraction is active. No network required."
    }
}
