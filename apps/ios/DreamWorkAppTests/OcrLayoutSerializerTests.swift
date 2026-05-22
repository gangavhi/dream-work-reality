import XCTest
@testable import DreamWorkApp

final class OcrLayoutSerializerTests: XCTestCase {
    func testOrdersBlocksTopToBottomThenLeftToRight() {
        let doc = VisionOcrAdapter.NormalizedDocument(pages: [
            VisionOcrAdapter.Page(blocks: [
                VisionOcrAdapter.TextBlock(
                    text: "Bottom",
                    confidence: 0.9,
                    bounds: VisionOcrAdapter.NormRect(x: 0.1, y: 0.1, width: 0.2, height: 0.05)
                ),
                VisionOcrAdapter.TextBlock(
                    text: "Top-Left",
                    confidence: 0.9,
                    bounds: VisionOcrAdapter.NormRect(x: 0.1, y: 0.8, width: 0.2, height: 0.05)
                ),
                VisionOcrAdapter.TextBlock(
                    text: "Top-Right",
                    confidence: 0.9,
                    bounds: VisionOcrAdapter.NormRect(x: 0.6, y: 0.8, width: 0.2, height: 0.05)
                ),
            ]),
        ])

        let lines = OcrLayoutSerializer.serialize(document: doc).components(separatedBy: "\n")
        XCTAssertEqual(lines, ["Top-Left", "Top-Right", "Bottom"])
    }

    func testLabelValuePairsFromSameRow() {
        let blocks = [
            OcrLayoutSerializer.LayoutBlock(text: "NAME", confidence: 1, x: 0.05, y: 0.5, width: 0.15, height: 0.04),
            OcrLayoutSerializer.LayoutBlock(text: "Jane Doe", confidence: 1, x: 0.35, y: 0.5, width: 0.3, height: 0.04),
        ]
        let pairs = OcrLayoutSerializer.labelValuePairs(from: blocks)
        XCTAssertEqual(pairs.count, 1)
        XCTAssertEqual(pairs[0].label, "NAME")
        XCTAssertEqual(pairs[0].value, "Jane Doe")
    }
}
