import XCTest

final class DreamWorkAppUITests: XCTestCase {
    func testHomeScreenTitleIsVisible() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.buttons["homeUploadDocumentButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 5))
    }

    func testPeopleScreenShowsLiveRustDataAfterSave() {
        let app = XCUIApplication()
        app.launch()

        app.tabBars.buttons["People"].tap()
        let loadSamples = app.buttons["peopleLoadSamplesButton"]
        XCTAssertTrue(loadSamples.waitForExistence(timeout: 5))
        loadSamples.tap()

        let list = app.tables["peopleList"]
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        XCTAssertTrue(list.cells.staticTexts["Alex Carter"].waitForExistence(timeout: 5))
        list.cells.staticTexts["Alex Carter"].firstMatch.tap()

        XCTAssertTrue(app.navigationBars["Alex Carter"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Edit all"].waitForExistence(timeout: 5))
    }
}
