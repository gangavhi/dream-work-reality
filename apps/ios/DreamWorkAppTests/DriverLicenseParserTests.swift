import XCTest
@testable import DreamWorkApp

final class DriverLicenseParserTests: XCTestCase {
    private func formatDOB(_ date: Date?) -> String? {
        guard let date else { return nil }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "MM/dd/yyyy"
        return df.string(from: date)
    }

    func testDemoTextParsesDOBAndAddress() {
        let result = DriverLicenseParser.parse(DriverLicenseParser.demoDriverLicenseText)
        XCTAssertEqual(formatDOB(result.dateOfBirth), "04/25/1990")
        XCTAssertEqual(result.addressLine1, "2457 MEADOWBROOK AVE")
        XCTAssertEqual(result.city, "AUSTIN")
        XCTAssertEqual(result.state, "TX")
        XCTAssertEqual(result.postalCode, "78701")
    }

    func testDOBOnNextLineAfterLabel() {
        let text = """
        DRIVER LICENSE
        DOB
        04/25/1990
        ISS 01/15/2024
        EXP 04/25/2028
        100 MAIN ST
        AUSTIN TX 78701
        """
        let result = DriverLicenseParser.parse(text)
        XCTAssertEqual(formatDOB(result.dateOfBirth), "04/25/1990")
        XCTAssertEqual(formatDOB(result.issueDate), "01/15/2024")
        XCTAssertEqual(formatDOB(result.expiryDate), "04/25/2028")
    }

    func testDoesNotUseExpiryAsDOB() {
        let text = """
        DRIVER LICENSE
        EXP 04/25/2028
        ISS 01/15/2024
        100 MAIN ST
        AUSTIN TX 78701
        """
        let result = DriverLicenseParser.parse(text)
        XCTAssertNil(result.dateOfBirth)
    }

    func testCaliforniaNumberedLayoutInfersStateFromAddressNotHardcodedTexas() {
        let text = """
        CALIFORNIA
        DRIVER LICENSE
        4d. DL: D12345678
        1. SMITH
        2. JANE
        8. Address
        742 OAK STREET
        SACRAMENTO, CA 95814
        3. DOB: 03/15/1985
        """
        let result = DriverLicenseParser.parse(text)
        XCTAssertEqual(result.state, "CA")
        XCTAssertEqual(result.city, "Sacramento")
    }

    func testLowercaseStateInAddress() {
        let text = """
        2457 Meadowbrook Ave
        Austin tx 78701
        """
        let result = DriverLicenseParser.parse(text)
        XCTAssertEqual(result.city, "Austin")
        XCTAssertEqual(result.state, "TX")
        XCTAssertEqual(result.postalCode, "78701")
    }

    static let texasSampleOCRText = """
    TEXAS
    DRIVER LICENSE
    4d. DL: D12345678
    3. DOB: 03/15/1985
    1. SMITH
    2. JANE
    8. Address
    742 OAK STREET
    AUSTIN, TX 78701-1234
    4a. Iss: 01/10/2023
    4b. Exp: 01/10/2028
    """

    /// Simulates noisy Vision OCR from a Texas DL photo.
    static let texasSampleNoisyOCRText = """
    * Texass
    DRIVER LICENSE
    LIMITED TERM
    4d. DL: D12345678
    з. дov: 03/1511985
    46. Exp: 01/10/2028
    4a. Iss:
    01/10/2023
    SMITH
    ¿ JANE
    8. 742 OAK STREET
    AUSTIN TX 78701-1234
    Ba. Eno NONE
    """

    func testTexasSampleLicenseMapsAllFields() {
        let result = DriverLicenseParser.parse(Self.texasSampleOCRText)
        let suggestions = DriverLicenseFieldMapper.suggestions(from: result)
        let byKey = Dictionary(uniqueKeysWithValues: suggestions.map { ($0.profileKey, $0.value) })

        XCTAssertEqual(byKey[ProfileFieldKey.displayName], "Jane Smith")
        XCTAssertEqual(byKey[ProfileFieldKey.legalFirstName], "Jane")
        XCTAssertEqual(byKey[ProfileFieldKey.legalLastName], "Smith")
        XCTAssertEqual(byKey[ProfileFieldKey.dateOfBirth], "03/15/1985")
        XCTAssertEqual(byKey[ProfileFieldKey.addressLine1], "742 Oak Street")
        XCTAssertEqual(byKey[ProfileFieldKey.city], "Austin")
        XCTAssertEqual(byKey[ProfileFieldKey.state], "TX")
        XCTAssertEqual(byKey[ProfileFieldKey.postalCode], "78701")
        XCTAssertEqual(byKey[ProfileFieldKey.driversLicenseIssueDate], "01/10/2023")
        XCTAssertEqual(byKey[ProfileFieldKey.driversLicenseExpiry], "01/10/2028")
        XCTAssertEqual(byKey[ProfileFieldKey.driversLicenseNumber], "D12345678")
        XCTAssertEqual(byKey[ProfileFieldKey.driversLicenseState], "TX")
    }

    func testTexasSampleNoisyOCRMapsAllFields() {
        let result = DriverLicenseParser.parse(Self.texasSampleNoisyOCRText)
        let byKey = Dictionary(uniqueKeysWithValues: DriverLicenseFieldMapper.suggestions(from: result).map { ($0.profileKey, $0.value) })

        XCTAssertEqual(byKey[ProfileFieldKey.displayName], "Jane Smith")
        XCTAssertEqual(byKey[ProfileFieldKey.legalFirstName], "Jane")
        XCTAssertEqual(byKey[ProfileFieldKey.legalLastName], "Smith")
        XCTAssertEqual(byKey[ProfileFieldKey.dateOfBirth], "03/15/1985")
        XCTAssertEqual(byKey[ProfileFieldKey.addressLine1], "742 Oak Street")
        XCTAssertEqual(byKey[ProfileFieldKey.driversLicenseIssueDate], "01/10/2023")
        XCTAssertEqual(byKey[ProfileFieldKey.driversLicenseExpiry], "01/10/2028")
    }

    func testAAMVABarcodeInlineFields() {
        let payload = """
        ANSI636000010002DL00410288
        DBB19900425
        DAG2457 MEADOWBROOK AVE
        DAIAUSTIN
        DAJTX
        DAK787010000
        """
        let result = DriverLicenseParser.parseAAMVAPDF417(payload)
        XCTAssertNotNil(result)
        XCTAssertEqual(formatDOB(result?.dateOfBirth), "04/25/1990")
        XCTAssertEqual(result?.addressLine1, "2457 MEADOWBROOK AVE")
        XCTAssertEqual(result?.city, "AUSTIN")
        XCTAssertEqual(result?.state, "TX")
        XCTAssertEqual(result?.postalCode, "787010000")
    }

    /// Vision often emits field 8 (address) before standalone surname/given lines on Texas DL photos.
    func testMisorderedTexasPhotoOCRLayout() {
        let text = """
        Director: StenC McCraw
        Stvonc MeCour
        DRIVER LICENSE
        TEXAS
        12. Rest A
        8. 2528 B.
        3.DOBZ
        4d. DL:
        SMITH
        JANEMICHAEL
        з. дov: 06/0241990
        06/02/1990
        06/02/1990
        D1234567
        87654321
        RIDGEWOOD
        78701-1234
        4b. Exp: 22/02/2027
        4a. Iss:
        22/09/2024
        """
        let result = DriverLicenseParser.parse(text)
        let byKey = Dictionary(uniqueKeysWithValues: DriverLicenseFieldMapper.suggestions(from: result).map { ($0.profileKey, $0.value) })

        XCTAssertEqual(byKey[ProfileFieldKey.legalLastName], "Smith")
        XCTAssertEqual(byKey[ProfileFieldKey.legalFirstName], "Janemichael")
        XCTAssertEqual(formatDOB(result.dateOfBirth), "06/02/1990")
        XCTAssertEqual(byKey[ProfileFieldKey.addressLine1], "2528 Ct")
        XCTAssertEqual(byKey[ProfileFieldKey.postalCode], "78701")
        XCTAssertEqual(byKey[ProfileFieldKey.city], "Ridgewood")
        XCTAssertEqual(byKey[ProfileFieldKey.driversLicenseNumber], "87654321")
        XCTAssertNotEqual(byKey[ProfileFieldKey.driversLicenseNumber], "78701-1234")
        XCTAssertEqual(formatDOB(result.expiryDate), "02/22/2027")
    }

    func testOcrFieldSuggesterUsesPersonNameResolverForTexasLicense() {
        let suggestions = OcrFieldSuggester.suggest(from: Self.texasSampleNoisyOCRText, documentType: .driversLicense)
        let byKey = Dictionary(uniqueKeysWithValues: suggestions.map { ($0.profileKey, $0.value) })

        XCTAssertEqual(byKey[ProfileFieldKey.displayName], "Jane Smith")
        XCTAssertEqual(byKey[ProfileFieldKey.legalFirstName], "Jane")
        XCTAssertEqual(byKey[ProfileFieldKey.legalLastName], "Smith")
    }
}
