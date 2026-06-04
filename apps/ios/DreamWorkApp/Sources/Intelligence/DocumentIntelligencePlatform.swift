import Foundation

/// Zero-egress local document intelligence platform — ten-layer pipeline facade.
enum DocumentIntelligencePlatform {
    /// Full local pipeline: intake → OCR → classify → route → extract → validate → normalize → confidence → profile schema.
    static func process(
        document: VisionOcrAdapter.NormalizedDocument,
        fileURL: URL? = nil,
        allowHeavyLLM: Bool = true
    ) async -> DocumentUnderstandingService.PipelineResult {
        await DocumentUnderstandingService.process(
            document: document,
            fileURL: fileURL,
            allowHeavyLLM: allowHeavyLLM
        )
    }
}
