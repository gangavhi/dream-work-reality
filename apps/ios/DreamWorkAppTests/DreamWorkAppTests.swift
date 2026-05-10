import XCTest
@testable import DreamWorkApp

@MainActor
final class DreamWorkAppTests: XCTestCase {
    func testRefreshStatusUsesMockServiceValue() {
        let appState = AppState(coreService: MockCoreBridgeService())

        appState.refreshStatus()

        XCTAssertEqual(appState.statusText, "Mock core bridge connected")
        XCTAssertEqual(appState.people.count, 1)
        XCTAssertEqual(appState.people.first?.displayTitle, "Mock Person")
    }

    func testRustCoreBridgeReturnsStatus() {
        let service = RustCoreBridgeService()
        let status = service.fetchStatus()
        XCTAssertTrue(status.contains("Rust core bridge connected"))
    }

    func testSaveAndLoadDemoPersonUsesCoreService() {
        let appState = AppState(coreService: RustCoreBridgeService())

        appState.saveAndLoadDemoPerson()

        XCTAssertEqual(appState.selectedPersonName, "Alex Carter")
        XCTAssertGreaterThanOrEqual(appState.manualEntryCount, 1)
        XCTAssertTrue(appState.people.contains { $0.id == "person-1" && $0.displayTitle == "Alex Carter" })
    }
}
