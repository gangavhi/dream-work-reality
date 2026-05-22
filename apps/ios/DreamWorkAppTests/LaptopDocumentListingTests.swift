import XCTest
@testable import DreamWorkApp

final class LaptopDocumentListingTests: XCTestCase {
    func testParseHTMLListingFindsSupportedFiles() {
        let html = """
        <html><body>
        <a href="sample-driver-license.png">sample-driver-license.png</a>
        <a href="notes.txt">notes.txt</a>
        <a href="sample.pdf">sample.pdf</a>
        </body></html>
        """
        let base = URL(string: "http://127.0.0.1:8010/")!
        let items = LaptopDocumentListing.parseHTMLListing(html: html, baseURL: base, sourceLabel: "Test")
        let names = Set(items.map(\.displayName))
        XCTAssertTrue(names.contains("sample-driver-license.png"))
        XCTAssertTrue(names.contains("sample.pdf"))
        XCTAssertFalse(names.contains("notes.txt"))
    }
}
