import Foundation

/// Controls when the ~380MB on-device GGUF may run automatically after a scan.
enum OnDeviceMLPolicy {
    #if DEBUG
    /// When true, simulator follows blocked-auto policy (for crash-regression tests).
    static var testSimulatePhysicalIPhone = false
    #endif

    /// ONNX always runs on scan; GGUF auto-runs when memory headroom allows.
    static var allowsAutomaticInferenceOnScan: Bool {
        #if DEBUG
        if testSimulatePhysicalIPhone {
            return false
        }
        #endif
        return GenAISettings.provider == .onDevice
    }

    /// Show manual extraction when auto GGUF may be skipped (low memory) or for a second pass.
    static var requiresManualExtractionTrigger: Bool {
        GenAISettings.provider == .onDevice
    }

    static let manualExtractionButtonTitle = "Run full on-device extraction"

    static let manualExtractionExplanationWhenFieldsPresent =
        "Basic field mapping ran on this device. Tap below to run the full local model again for additional fields, or edit values manually."

    static let manualExtractionExplanation =
        "Field mapping runs automatically after each scan when memory allows. If fields are missing, tap below to run the full local model, or enter details manually."

    static var autoGGUFDeferredNotice: String {
        "Full on-device extraction will run automatically when memory allows. Tap below to run it now, or enter fields manually."
    }
}
