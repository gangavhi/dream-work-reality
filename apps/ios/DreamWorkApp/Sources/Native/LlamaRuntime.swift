import Foundation

/// Releases the globally cached GGUF weights so a different on-device model can load safely.
enum LlamaRuntime {
    static func releaseCachedModel() {
        dreamwork_llama_release_cached_model()
    }
}

@_silgen_name("dreamwork_llama_release_cached_model")
private func dreamwork_llama_release_cached_model()
