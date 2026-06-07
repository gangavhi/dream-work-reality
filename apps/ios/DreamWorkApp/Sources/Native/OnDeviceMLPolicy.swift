import Foundation

/// Scan-review UX policy for rewrite v2 (on-device only, no remote AI).
enum OnDeviceMLPolicy {
    #if DEBUG
    static var testSimulatePhysicalIPhone = false
    #endif

    static var allowsAutomaticInferenceOnScan: Bool {
        #if DEBUG
        if testSimulatePhysicalIPhone { return false }
        #endif
        return true
    }

    static var manualExtractionButtonTitle: String {
        "Run document extraction again"
    }

    static var manualExtractionExplanation: String {
        "Extraction uses Apple Vision and NaturalLanguage on this device. Tap to re-run if fields look incomplete."
    }

    static func shouldShowManualExtractionRetry(heavyLLMDeferred: Bool, suggestionsEmpty: Bool) -> Bool {
        _ = heavyLLMDeferred
        #if DEBUG
        return suggestionsEmpty
        #else
        return false
        #endif
    }
}
