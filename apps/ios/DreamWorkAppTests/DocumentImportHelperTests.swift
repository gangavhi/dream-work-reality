import XCTest

@testable import DreamWorkApp

final class DocumentImportHelperTests: XCTestCase {
    func testDetectsPDFByMagicBytesWithoutExtension() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("trustnest-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }

        try Data("%PDF-1.4\n%EOF".utf8).write(to: url)
        XCTAssertTrue(DocumentImportHelper.isPDF(url))
        XCTAssertEqual(DocumentImportHelper.contentKind(for: url), .pdf)
    }

    func testDetectsJPEGByMagicBytes() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("trustnest-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }

        var bytes = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])
        bytes.append(contentsOf: [UInt8](repeating: 0, count: 8))
        try bytes.write(to: url)
        XCTAssertTrue(DocumentImportHelper.isRaster(url))
        XCTAssertEqual(DocumentImportHelper.contentKind(for: url), .raster)
    }
}
