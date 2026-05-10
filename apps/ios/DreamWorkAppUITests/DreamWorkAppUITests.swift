import XCTest

final class DreamWorkAppUITests: XCTestCase {
    func testHomeScreenTitleIsVisible() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["homeScreenTitle"].waitForExistence(timeout: 5))
    }

    func testPeopleScreenShowsLiveRustDataAfterSave() {
        let app = XCUIApplication()
        app.launch()

        app.tabBars.buttons["People"].tap()
        let addSamples = app.buttons["peopleAddSamplesButton"]
        XCTAssertTrue(addSamples.waitForExistence(timeout: 5))
        addSamples.tap()

        let list = app.tables["peopleList"]
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        XCTAssertTrue(list.cells.staticTexts["Alex Carter"].waitForExistence(timeout: 5))
        list.cells.staticTexts["Alex Carter"].firstMatch.tap()

        XCTAssertTrue(app.staticTexts["personDetailDisplayName"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Alex Carter"].exists)
    }
}
