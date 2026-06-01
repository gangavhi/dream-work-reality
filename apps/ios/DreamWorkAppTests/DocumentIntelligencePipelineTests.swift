import XCTest
@testable import DreamWorkApp

final class DocumentIntelligencePipelineTests: XCTestCase {
    func testPipelineFailsClosedWithoutLocalMLModels() async {
        let doc = VisionOcrAdapter.NormalizedDocument(pages: [
            VisionOcrAdapter.Page(blocks: [
                VisionOcrAdapter.TextBlock(
                    text: "TEXAS DRIVER LICENSE",
                    confidence: 0.96,
                    bounds: VisionOcrAdapter.NormRect(x: 0.1, y: 0.9, width: 0.6, height: 0.05)
                ),
                VisionOcrAdapter.TextBlock(
                    text: "First Name: Jane",
                    confidence: 0.95,
                    bounds: VisionOcrAdapter.NormRect(x: 0.1, y: 0.8, width: 0.4, height: 0.05)
                ),
                VisionOcrAdapter.TextBlock(
                    text: "Last Name: Smith",
                    confidence: 0.95,
                    bounds: VisionOcrAdapter.NormRect(x: 0.1, y: 0.7, width: 0.4, height: 0.05)
                ),
                VisionOcrAdapter.TextBlock(
                    text: "DOB: 03/15/1985",
                    confidence: 0.95,
                    bounds: VisionOcrAdapter.NormRect(x: 0.1, y: 0.6, width: 0.4, height: 0.05)
                ),
                VisionOcrAdapter.TextBlock(
                    text: "License No: D12345678",
                    confidence: 0.95,
                    bounds: VisionOcrAdapter.NormRect(x: 0.1, y: 0.5, width: 0.5, height: 0.05)
                ),
            ]),
        ])

        let previous = GenAISettings.provider
        GenAISettings.provider = .off
        defer { GenAISettings.provider = previous }

        let result = await DocumentIntelligencePipeline.extract(document: doc)
        XCTAssertTrue(result.pipelineTrace.contains { $0.hasPrefix("classify:") })
        XCTAssertTrue(
            result.pipelineTrace.contains("classify:document.classifier.v1:classifier_skipped:provider_off")
                || result.pipelineTrace.contains("classify:skipped:single_pass_parser")
                || result.pipelineTrace.contains("classify:keyword:classifier_active:keyword")
        )
        XCTAssertTrue(result.pipelineTrace.contains("template:disabled:ml_only"))
        XCTAssertTrue(result.pipelineTrace.contains("extract:ml_failed"))
        XCTAssertTrue(result.pipelineTrace.contains { $0.hasPrefix("identity_graph:") })
        XCTAssertTrue(result.suggestions.isEmpty)
        XCTAssertFalse(result.usedHeuristicFallback)
    }

    func testExtractDoesNotUseUniversalParserWhenLLMOff() async {
        let doc = VisionOcrAdapter.NormalizedDocument(pages: [
            VisionOcrAdapter.Page(blocks: [
                VisionOcrAdapter.TextBlock(
                    text: "SOCIAL SECURITY",
                    confidence: 0.95,
                    bounds: VisionOcrAdapter.NormRect(x: 0, y: 0.9, width: 0.5, height: 0.05)
                ),
                VisionOcrAdapter.TextBlock(
                    text: "123-45-6789",
                    confidence: 0.95,
                    bounds: VisionOcrAdapter.NormRect(x: 0, y: 0.7, width: 0.3, height: 0.05)
                ),
            ]),
        ])

        let previous = GenAISettings.provider
        GenAISettings.provider = .off
        defer { GenAISettings.provider = previous }

        let result = await DocumentIntelligencePipeline.extract(document: doc)
        XCTAssertFalse(result.usedHeuristicFallback)
        XCTAssertFalse(result.suggestions.contains { $0.profileKey == ProfileFieldKey.ssn })
        XCTAssertTrue(result.suggestions.isEmpty)
    }
}
