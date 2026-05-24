import XCTest
@testable import DreamWorkApp

final class DocumentIntelligencePipelineTests: XCTestCase {
    func testExtractUsesUniversalParserWhenLLMOff() async {
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
        XCTAssertTrue(result.usedHeuristicFallback || result.suggestions.contains { $0.profileKey == ProfileFieldKey.ssn })
        XCTAssertTrue(result.suggestions.contains { $0.profileKey == ProfileFieldKey.ssn })
        let ssn = result.suggestions.first { $0.profileKey == ProfileFieldKey.ssn }
        XCTAssertNotNil(ssn?.confidenceBreakdown)
        XCTAssertTrue(ssn?.requiresManualConfirmation ?? true)
    }
}
