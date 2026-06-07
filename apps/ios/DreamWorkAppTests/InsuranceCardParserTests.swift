import XCTest
@testable import DreamWorkApp

final class InsuranceCardParserTests: XCTestCase {
    static let sampleUHCPortalOCR = """
    Jordan Lee's ID Cards as of 06/07/2026
    DOB: 06/05/1995
    Medical
    Front
    Back
    """

    static let sampleBlueCrossOCR = """
    BLUE CROSS BLUE SHIELD
    MEMBER ID: ABC123456789
    GROUP #: GRP001
    SUBSCRIBER: ALEX RIVERA
    """

    func testDetectsUHCPortalExport() {
        XCTAssertTrue(InsuranceCardParser.isInsuranceCard(Self.sampleUHCPortalOCR))
    }

    func testParsesUHCPortalHolderNameAndDOB() {
        let suggestions = InsuranceCardParser.suggestions(from: Self.sampleUHCPortalOCR)
        let byKey = Dictionary(uniqueKeysWithValues: suggestions.map { ($0.profileKey, $0.value) })
        XCTAssertEqual(byKey[ProfileFieldKey.legalFirstName], "Jordan")
        XCTAssertEqual(byKey[ProfileFieldKey.legalLastName], "Lee"
        XCTAssertEqual(byKey[ProfileFieldKey.dateOfBirth], "06/05/1995")
    }

    func testParsesStandardInsuranceCard() {
        let suggestions = InsuranceCardParser.suggestions(from: Self.sampleBlueCrossOCR)
        let byKey = Dictionary(uniqueKeysWithValues: suggestions.map { ($0.profileKey, $0.value) })
        XCTAssertEqual(byKey[ProfileFieldKey.insuranceCarrier], "Blue Cross Blue Shield")
        XCTAssertEqual(byKey[ProfileFieldKey.insuranceMemberId], "ABC123456789")
    }

    func testParsesNoisyUHCMemberIdByFrequency() {
        let noisy = """
        Alex Lee's ID Cards as of 06/07/2026
        DOB: 06/02/1990
        Medical
        Front Back
        0000210008
        0000210008
        0000210008
        SOZO
        400
        """
        let suggestions = InsuranceCardParser.suggestions(from: noisy)
        let byKey = Dictionary(uniqueKeysWithValues: suggestions.map { ($0.profileKey, $0.value) })
        XCTAssertEqual(byKey[ProfileFieldKey.insuranceMemberId], "0000210008")
        XCTAssertEqual(byKey[ProfileFieldKey.legalLastName], "Lee")
    }
}
