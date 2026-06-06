import Foundation

/// Legacy ONNX MiniLM slot — disabled on the Apple-native pipeline (`ganga-2026-05-16-3`).
/// NaturalLanguage + Create ML handle field-label semantics instead.
final class MiniLMOnnxFieldEmbedder: @unchecked Sendable {
    static let shared = MiniLMOnnxFieldEmbedder()

    static let artifactID = "embed.minilm.v1"
    static let hiddenSize = 384

    private init() {}

    var isAvailable: Bool { false }

    var statusToken: String { "\(Self.artifactID):disabled:apple_native" }

    func embed(_ text: String) -> [Float]? { nil }

    func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Double = 0
        for i in a.indices {
            dot += Double(a[i]) * Double(b[i])
        }
        return dot
    }
}
