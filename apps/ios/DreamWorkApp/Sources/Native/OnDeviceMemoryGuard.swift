import Darwin
import Foundation

/// Prevents loading ~400MB GGUF weights when iOS reports insufficient headroom (jetsam).
enum OnDeviceMemoryGuard {
    /// Roughly: GGUF mmap + context KV + decode scratch.
    private static let minimumAvailableBytes: UInt64 = 320 * 1024 * 1024

    static func mayRunHeavyInference() -> Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return availableMemoryBytes() >= minimumAvailableBytes
        #endif
    }

    static var skipTraceToken: String {
        mayRunHeavyInference() ? "ok" : "available_memory_low"
    }

    static var userFacingSkipNotice: String {
        "On-device AI was skipped because the phone is low on memory after OCR. You can still enter fields manually, or try again after closing other apps."
    }

    private static func availableMemoryBytes() -> UInt64 {
        let bytes = UInt64(os_proc_available_memory())
        if bytes > 0 {
            return bytes
        }
        return UInt64(ProcessInfo.processInfo.physicalMemory / 4)
    }
}
