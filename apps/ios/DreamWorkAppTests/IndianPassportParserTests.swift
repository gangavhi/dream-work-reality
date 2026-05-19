import XCTest
@testable import DreamWorkApp

final class IndianPassportParserTests: XCTestCase {
    /// Synthetic Indian passport biodata + MRZ (no real PII).
    static let sampleIndianPassportOCRText = """
    REPUBLIC OF INDIA
    Passport No. M1234567
    Surname
    PATEL
    Given Name(s)
    AMIT
    Nationality INDIAN
    Date of Birth 15/03/1985
    Place of Birth MUMBAI, MAHARASHTRA
    Place of Issue NEW DELHI
    Date of Issue 01/01/2020
    Date of Expiry 01/01/2030
    P<INDPATEL<<AMIT<<<<<<<<<<<<<<<<<<<<<<<<<
    M1234567<0IND8503150M3001015<<<<<<<<<<<<<<04
    """

    static let sampleNoisyIndianPassportOCRText = """
    REPUBLIC OF INDIA
    Passport~do
    PATEL
    AMIT.0
    INDIAN
    02ID6/1990
    KAVALI, ANDHRA PRADESH
    HYDERABAD
    27'/12/2Q14
    26./.12/24.24
    P<INDPATEL<<AMIT<<<<<<<<<<<<<<<<<<<<<<<<<
    M1234567<6IND9006027M2412265<<<<<<<<<<<<<<04
    """

    func testParsesCleanIndianPassportFields() {
        let suggestions = IndianPassportParser.suggestions(from: Self.sampleIndianPassportOCRText)
        let byKey = Dictionary(uniqueKeysWithValues: suggestions.map { ($0.profileKey, $0.value) })

        XCTAssertEqual(byKey[ProfileFieldKey.displayName], "Amit Patel")
        XCTAssertEqual(byKey[ProfileFieldKey.legalFirstName], "Amit")
        XCTAssertEqual(byKey[ProfileFieldKey.legalLastName], "Patel")
        XCTAssertEqual(byKey[ProfileFieldKey.passportNumber], "M1234567")
        XCTAssertEqual(byKey[ProfileFieldKey.dateOfBirth], "15/03/1985")
        XCTAssertEqual(byKey[ProfileFieldKey.passportExpiry], "01/01/2030")
        XCTAssertEqual(byKey[ProfileFieldKey.passportCountry], "IND")
    }

    func testParsesNoisyIndianPassportFields() {
        let suggestions = IndianPassportParser.suggestions(from: Self.sampleNoisyIndianPassportOCRText)
        let byKey = Dictionary(uniqueKeysWithValues: suggestions.map { ($0.profileKey, $0.value) })

        XCTAssertEqual(byKey[ProfileFieldKey.legalLastName], "Patel")
        XCTAssertEqual(byKey[ProfileFieldKey.legalFirstName], "Amit")
        XCTAssertEqual(byKey[ProfileFieldKey.displayName], "Amit Patel")
        XCTAssertEqual(byKey[ProfileFieldKey.passportNumber], "M1234567")
        XCTAssertEqual(byKey[ProfileFieldKey.dateOfBirth], "02/06/1990")
        XCTAssertEqual(byKey[ProfileFieldKey.passportExpiry], "26/12/2024")
        XCTAssertEqual(byKey[ProfileFieldKey.passportCountry], "IND")
        XCTAssertEqual(byKey[ProfileFieldKey.country], "IN")
    }

    func testOcrFieldSuggesterPrefersIndianParser() {
        let suggestions = OcrFieldSuggester.suggest(from: Self.sampleNoisyIndianPassportOCRText, documentType: .passport)
        let byKey = Dictionary(uniqueKeysWithValues: suggestions.map { ($0.profileKey, $0.value) })
        XCTAssertEqual(byKey[ProfileFieldKey.displayName], "Amit Patel")
        XCTAssertEqual(byKey[ProfileFieldKey.dateOfBirth], "02/06/1990")
        XCTAssertEqual(byKey[ProfileFieldKey.passportExpiry], "26/12/2024")
    }

    func testClassifiesIndianPassportDocumentType() {
        let classification = DocumentTypeClassifier.classify(from: Self.sampleIndianPassportOCRText)
        XCTAssertEqual(classification.documentType, .passport)
        XCTAssertGreaterThanOrEqual(classification.confidence, 0.88)
    }

    func testOcrFieldSuggesterRoutesIndianPassport() {
        let suggestions = OcrFieldSuggester.suggest(from: Self.sampleIndianPassportOCRText, documentType: .passport)
        let byKey = Dictionary(uniqueKeysWithValues: suggestions.map { ($0.profileKey, $0.value) })
        XCTAssertEqual(byKey[ProfileFieldKey.displayName], "Amit Patel")
        XCTAssertEqual(byKey[ProfileFieldKey.passportNumber], "M1234567")
    }
}
