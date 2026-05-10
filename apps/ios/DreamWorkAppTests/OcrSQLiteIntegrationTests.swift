import XCTest

@testable import DreamWorkApp

/// End-to-end OCR on a real-world JPEG (copied from `~/Downloads/driver license-first.jpeg` into `Fixtures/`),
/// persisted via Rust → SQLite `extraction_run`.
@MainActor
final class OcrSQLiteIntegrationTests: XCTestCase {
    func testDriverLicenseImageOcrPersistsExtractionRunToSQLite() async throws {
        let bridge = RustCoreBridgeService()
        let runsBefore = bridge.extractionRunCount()

        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: "driver-license-first", withExtension: "jpeg") else {
            XCTFail(
                "Fixture missing: add DreamWorkAppTests/Fixtures/driver-license-first.jpeg and XcodeGen resources entry."
            )
            return
        }

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
            "Vision should detect at least one text region on the driver license image"
        )

        let runsAfter = bridge.extractionRunCount()
        XCTAssertEqual(
            runsAfter,
            runsBefore + 1,
            "ingest_normalized_document should append one extraction_run row in SQLite"
        )
    }
}
