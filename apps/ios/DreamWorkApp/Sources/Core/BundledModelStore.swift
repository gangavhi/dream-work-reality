import Foundation

/// Optional bundled artifacts (Create ML, legacy Rust planner). Apple NL is the default path.
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

    /// Legacy Rust storage planner GGUF (optional; `AppleStoragePlanner` is default).
    static func storagePlannerArtifactPath() -> String? {
        artifactPath(artifactID: "sql.storage.planner.v1")
    }

    static func installStatusMessage() -> String {
        if CreateMLModelRegistry.hasBundledClassifier || CreateMLModelRegistry.hasBundledFieldTagger {
            return "Apple Vision + NaturalLanguage are active. Optional Create ML models are installed for higher document-type accuracy."
        }
        return "Apple Vision OCR, NaturalLanguage field mapping, and barcode/MRZ parsing run on-device. Add Create ML models under Resources/MLModels for optional tuning."
    }
}
