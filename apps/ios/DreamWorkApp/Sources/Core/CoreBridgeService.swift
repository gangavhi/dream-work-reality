import Foundation

protocol CoreBridgeService {
    func fetchStatus() -> String
    func saveManualEntry(id: String, displayName: String) -> Bool
    func readManualEntryName(id: String) -> String?
    func manualEntryCount() -> Int
}

@_silgen_name("dreamwork_fetch_status")
private func dreamwork_fetch_status() -> UnsafeMutablePointer<CChar>?

@_silgen_name("dreamwork_string_free")
private func dreamwork_string_free(_ pointer: UnsafeMutablePointer<CChar>?)

@_silgen_name("dreamwork_save_manual_entry")
private func dreamwork_save_manual_entry(
    _ id: UnsafePointer<CChar>?,
    _ displayName: UnsafePointer<CChar>?
) -> Bool

@_silgen_name("dreamwork_read_manual_entry_name")
private func dreamwork_read_manual_entry_name(_ id: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?

@_silgen_name("dreamwork_manual_entry_count")
private func dreamwork_manual_entry_count() -> UInt32

struct RustCoreBridgeService: CoreBridgeService {
    func fetchStatus() -> String {
        guard let raw = dreamwork_fetch_status() else {
            return "Rust core unavailable"
        }
        defer { dreamwork_string_free(raw) }
        return String(cString: raw)
    }

    func saveManualEntry(id: String, displayName: String) -> Bool {
        id.withCString { idPtr in
            displayName.withCString { namePtr in
                dreamwork_save_manual_entry(idPtr, namePtr)
            }
        }
    }

    func readManualEntryName(id: String) -> String? {
        id.withCString { idPtr in
            guard let raw = dreamwork_read_manual_entry_name(idPtr) else {
                return nil
            }
            defer { dreamwork_string_free(raw) }
            return String(cString: raw)
        }
    }

    func manualEntryCount() -> Int {
        Int(dreamwork_manual_entry_count())
    }
}

struct MockCoreBridgeService: CoreBridgeService {
    func fetchStatus() -> String {
        "Mock core bridge connected"
    }

    func saveManualEntry(id: String, displayName: String) -> Bool {
        true
    }

    func readManualEntryName(id: String) -> String? {
        "Mock Person"
    }

    func manualEntryCount() -> Int {
        1
    }
}
