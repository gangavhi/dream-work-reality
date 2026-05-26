import Foundation

/// Locates required on-device model weights. TestFlight builds can ship models inside the app
/// bundle, while local/dev installs may sideload them under Application Support.
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

    static func artifactPath(artifactID: String) -> String? {
        guard let manifest = manifest(),
              let artifact = manifest.artifacts.first(where: { $0.artifact_id == artifactID })
        else { return nil }
        let installedPath = modelsDirectory.appendingPathComponent(artifact.filename).path
        if FileManager.default.fileExists(atPath: installedPath) {
            return installedPath
        }
        if let bundled = Bundle.main.url(
            forResource: artifact.filename,
            withExtension: nil,
            subdirectory: "Models"
        ) {
            return bundled.path
        }
        if let bundled = Bundle.main.url(forResource: artifact.filename, withExtension: nil) {
            return bundled.path
        }
        return nil
    }

    static func liteArtifactPath() -> String? {
        artifactPath(artifactID: "llm.schema.lite.v1")
    }

    static func documentClassifierArtifactPath() -> String? {
        artifactPath(artifactID: "document.classifier.v1")
    }

    static func storagePlannerArtifactPath() -> String? {
        artifactPath(artifactID: "sql.storage.planner.v1")
    }

    static func installStatusMessage() -> String {
        if liteArtifactPath() != nil,
           documentClassifierArtifactPath() != nil,
           storagePlannerArtifactPath() != nil
        {
            return "Required local ML models are installed. Classification, parsing, and storage planning run locally with no heuristic fallback."
        }
        if let artifact = manifest()?.artifacts.first(where: { $0.artifact_id == "llm.schema.lite.v1" }) {
            let gb = Double(artifact.bytes_approx ?? 0) / 1_000_000_000.0
            return String(format: "Required local ML models are not fully installed. Parser artifact %@ (~%.1f GB) is required, and classifier/storage planner artifacts must also be installed before the strict ML pipeline can complete.", artifact.filename, gb)
        }
        return "Required on-device parser model manifest is missing. Document data parsing is unavailable."
    }
}
