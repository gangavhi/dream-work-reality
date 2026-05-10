import Foundation
import Vision

/// Maps Vision observations into the normalized OCR JSON shape consumed by the Rust core (`dreamwork_ocr_apply_normalized_json`).
enum VisionOcrAdapter {
    struct NormalizedDocument: Codable {
        var pages: [Page]
    }

    struct Page: Codable {
        var blocks: [TextBlock]
    }

    struct TextBlock: Codable {
        var text: String
        var confidence: Float
        var bounds: NormRect
    }

    struct NormRect: Codable {
        var x: Float
        var y: Float
        var width: Float
        var height: Float
    }

    /// Vision reports bounding boxes in normalized **unit** coordinates (0…1); no pixel canvas is required.
    static func normalizedDocument(from observations: [VNRecognizedTextObservation]) -> NormalizedDocument {
        let blocks: [TextBlock] = observations.compactMap { obs in
            guard let candidate = obs.topCandidates(1).first else { return nil }
            let box = obs.boundingBox
            return TextBlock(
                text: candidate.string,
                confidence: Float(obs.confidence),
                bounds: NormRect(
                    x: Float(box.origin.x),
                    y: Float(1.0 - box.origin.y - box.height),
                    width: Float(box.width),
                    height: Float(box.height)
                )
            )
        }
        return NormalizedDocument(pages: [Page(blocks: blocks)])
    }

    static func encodeNormalizedDocumentJSON(_ document: NormalizedDocument) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(document) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
