import Foundation

/// Controls when the ~380MB on-device GGUF may run on a physical iPhone.
///
/// TestFlight crashes traced to automatic llama inference during scan (jetsam + native batch
/// pressure). On real devices we only run the model when the user explicitly requests it.
enum OnDeviceMLPolicy {
    #if DEBUG
    /// When true, simulator follows the physical-iPhone policy (no automatic LLM after scan).
    static var testSimulatePhysicalIPhone = false
    #endif

    /// Simulator/dev may still auto-run for faster iteration.
    static var allowsAutomaticInferenceOnScan: Bool {
        #if DEBUG
        if testSimulatePhysicalIPhone {
            return false
        }
        #endif
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    static var requiresManualExtractionTrigger: Bool {
        !allowsAutomaticInferenceOnScan
    }

    static let manualExtractionButtonTitle = "Extract fields on this device"

    static let manualExtractionExplanationWhenFieldsPresent =
        "Basic field mapping ran on this device. Tap below to run the full local model for additional fields, or edit values manually."

    static let manualExtractionExplanation =
        "On iPhone, the full on-device AI model does not start automatically after a scan because loading it can exceed available memory and crash the app. Basic field mapping still runs on device. Tap the button below for deeper extraction, or enter fields manually."
}
