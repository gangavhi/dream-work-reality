import Foundation

/// Controls when the ~380MB on-device GGUF may run on a physical iPhone.
///
/// TestFlight crashes traced to automatic llama inference during scan (jetsam + native batch
/// pressure). On real devices we only run the model when the user explicitly requests it.
enum OnDeviceMLPolicy {
    /// Simulator/dev may still auto-run for faster iteration.
    static var allowsAutomaticInferenceOnScan: Bool {
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

    static let manualExtractionExplanation =
        "On iPhone, on-device AI does not start automatically after a scan because loading the local model can exceed available memory and crash the app. Tap the button below when you want to run extraction, or enter fields manually."
}
