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
        let saveButton = app.buttons["peopleSaveLoadButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.tap()

        XCTAssertTrue(app.staticTexts["peopleLoadedPersonName"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Loaded person: Alex Carter"].exists)
    }
}
