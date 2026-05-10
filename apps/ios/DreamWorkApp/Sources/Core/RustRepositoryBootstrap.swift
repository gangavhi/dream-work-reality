import Foundation
import OSLog

/// Ensures the Rust core opens file-backed SQLite under Application Support before any FFI calls.
enum RustRepositoryBootstrap {
    private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "DreamWorkApp",
        category: "RustRepository"
    )

    private static let configured: Bool = {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            log.error("Application Support directory unavailable")
            return false
        }
        let directory = base.appendingPathComponent("DreamWork", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            log.error("Could not create DreamWork Application Support directory: \(String(describing: error))")
            return false
        }
        let databaseURL = directory.appendingPathComponent("library.sqlite", isDirectory: false)
        let ok = databaseURL.path.withCString { dreamwork_repository_configure_persistent_sqlite($0) }
        if !ok {
            log.error("Rust repository rejected persistent SQLite path (duplicate configure or invalid path)")
        }
        return ok
    }()

    static func ensureConfiguredForRustCalls() {
        _ = configured
    }
}

@_silgen_name("dreamwork_repository_configure_persistent_sqlite")
private func dreamwork_repository_configure_persistent_sqlite(_ pathUtf8: UnsafePointer<CChar>) -> Bool
