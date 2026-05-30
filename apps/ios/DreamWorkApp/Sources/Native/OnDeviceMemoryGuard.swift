import Darwin
import Foundation
import MachO

/// Prevents loading ~400MB GGUF weights when iOS reports insufficient headroom (jetsam).
enum OnDeviceMemoryGuard {
    /// Roughly: GGUF mmap + context KV + decode scratch.
    private static let minimumAvailableBytes: UInt64 = 320 * 1024 * 1024

    struct Snapshot: Sendable {
        let availableBytes: UInt64
        let physicalBytes: UInt64
        let residentBytes: UInt64

        var availableMegabytes: Double { Double(availableBytes) / 1_048_576.0 }
        var residentMegabytes: Double { Double(residentBytes) / 1_048_576.0 }

        var logLine: String {
            String(
                format: "mem avail=%.1fMB resident=%.1fMB physical=%.1fMB",
                availableMegabytes,
                residentMegabytes,
                Double(physicalBytes) / 1_048_576.0
            )
        }
    }

    #if DEBUG
    /// When true, simulator uses the same memory threshold as a physical iPhone.
    static var testTreatSimulatorLikeDevice = false
    /// When true, heavy inference is blocked (simulates post-OCR low memory).
    static var testForceLowMemory = false
    #endif

    static func snapshot() -> Snapshot {
        Snapshot(
            availableBytes: availableMemoryBytes(),
            physicalBytes: UInt64(ProcessInfo.processInfo.physicalMemory),
            residentBytes: currentResidentBytes()
        )
    }

    static func mayRunHeavyInference() -> Bool {
        #if DEBUG
        if testForceLowMemory {
            return false
        }
        #endif
        #if targetEnvironment(simulator)
        #if DEBUG
        if testTreatSimulatorLikeDevice {
            return availableMemoryBytes() >= minimumAvailableBytes
        }
        #endif
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

    static var minimumRequiredMegabytes: Double {
        Double(minimumAvailableBytes) / 1_048_576.0
    }

    private static func availableMemoryBytes() -> UInt64 {
        let bytes = UInt64(os_proc_available_memory())
        if bytes > 0 {
            return bytes
        }
        return UInt64(ProcessInfo.processInfo.physicalMemory / 4)
    }

    private static func currentResidentBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPointer in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), intPointer, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return UInt64(info.resident_size)
    }
}

#if DEBUG
/// Holds RAM to reproduce post-OCR memory pressure in simulator tests.
final class MemoryPressureSimulator {
    private var buffer: [UInt8]?

    @discardableResult
    func allocate(megabytes: Int) -> Bool {
        let byteCount = megabytes * 1_024 * 1_024
        guard byteCount > 0 else { return false }
        buffer = [UInt8](repeating: 0xA5, count: byteCount)
        return buffer != nil
    }

    func release() {
        buffer = nil
    }

    deinit {
        release()
    }
}
#endif
