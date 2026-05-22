import XCTest

@testable import DreamWorkApp

/// End-to-end OCR on a document image, persisted via Rust → SQLite `extraction_run`.
/// Add your own test image at `DreamWorkAppTests/Fixtures/sample-document.jpeg` to run locally.
@MainActor
final class OcrSQLiteIntegrationTests: XCTestCase {
    func testDocumentImageOcrPersistsExtractionRunToSQLite() async throws {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: "sample-document", withExtension: "jpeg")
            ?? bundle.url(forResource: "sample-document", withExtension: "jpg")
            ?? bundle.url(forResource: "sample-document", withExtension: "png")
        else {
            throw XCTSkip("No sample document fixture — add DreamWorkAppTests/Fixtures/sample-document.jpeg to run locally.")
        }

        let bridge = RustCoreBridgeService()
        let runsBefore = bridge.extractionRunCount()

        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let summary = try await DocumentTextExtractor.extractAndPersist(from: url) { json in
            bridge.ingestNormalizedDocumentJSON(json)
        }

        XCTAssertEqual(summary.pageCount, 1, "Single raster image should produce one normalized page")
        XCTAssertGreaterThan(
            summary.blockCount,
            0,
            "Vision should detect at least one text region on the document image"
        )

        let runsAfter = bridge.extractionRunCount()
        XCTAssertEqual(
            runsAfter,
            runsBefore + 1,
            "ingest_normalized_document should append one extraction_run row in SQLite"
        )
    }
}
