import XCTest
@testable import DreamWorkApp

@MainActor
final class DreamWorkAppTests: XCTestCase {
    func testRefreshStatusUsesMockServiceValue() {
        let appState = AppState(coreService: MockCoreBridgeService())

        appState.refreshStatus()

        XCTAssertEqual(appState.statusText, "Mock core bridge connected")
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
    }
}
