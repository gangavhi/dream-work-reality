import Foundation
import Vision

/// Optional PaddleOCR fallback (`paddle.ocr.v1`). Returns nil until CoreML/ONNX artifact is installed.
enum PaddleOcrAdapter {
    static let lowConfidenceThreshold: Float = 0.62

    static var isAvailable: Bool {
        if case .installed = ModelArtifactRegistry.loadState(for: .paddleOCR) { return true }
        return false
    }

    static func recognizePageBlocksIfNeeded(
        from cgImage: CGImage,
        visionBlocks: [VisionOcrAdapter.TextBlock]
    ) -> [VisionOcrAdapter.TextBlock]? {
        guard isAvailable else { return nil }
        guard averageConfidence(visionBlocks) < lowConfidenceThreshold else { return nil }
        // Artifact slot reserved — wire PP-OCR CoreML output to NormalizedDocument blocks here.
        _ = cgImage
        return nil
    }

    static func averageConfidence(_ blocks: [VisionOcrAdapter.TextBlock]) -> Float {
        guard !blocks.isEmpty else { return 0 }
        return blocks.reduce(0) { $0 + $1.confidence } / Float(blocks.count)
    }
}
