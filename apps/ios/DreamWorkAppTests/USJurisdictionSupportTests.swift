import XCTest
@testable import DreamWorkApp

final class USJurisdictionSupportTests: XCTestCase {
    func testInfersStateFromCityStateZipLine() {
        XCTAssertEqual(
            USJurisdictionSupport.inferStateCode(from: ["RIDGEWOOD TX 78701-1234"]),
            "TX"
        )
    }

    func testInfersStateFromHeaderName() {
        let lines = [
            "FLORIDA",
            "DRIVER LICENSE",
            "4d. DL: D12345678",
        ]
        XCTAssertEqual(USJurisdictionSupport.inferStateCode(from: lines), "FL")
    }

    func testInfersStateFromPlaceOfBirthText() {
        XCTAssertEqual(
            USJurisdictionSupport.inferStateCode(fromPlaceText: "TEXAS, U.S.A."),
            "TX"
        )
        XCTAssertEqual(
            USJurisdictionSupport.inferStateCode(fromPlaceText: "LOS ANGELES, CALIFORNIA"),
            "CA"
        )
    }

    func testDoesNotDefaultToTexasWithoutSignals() {
        XCTAssertNil(USJurisdictionSupport.inferStateCode(from: ["DRIVER LICENSE", "4d. DL: 12345678"]))
    }
}
