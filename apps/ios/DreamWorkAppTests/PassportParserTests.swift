import XCTest
@testable import DreamWorkApp

final class PassportParserTests: XCTestCase {
    /// Synthetic US passport biodata + MRZ (no real PII).
    static let sampleUSPassportOCRText = """
    UNITED STATES OF AMERICA
    PASSPORT
    Surname / Nom / Apellidos
    SMITH
    Given names / Prénoms / Nombres
    JANE MICHAEL
    Passport No. / No. du Passeport / No. de Pasaporte
    P12345678
    Nationality / Nationalité / Nacionalidad
    UNITED STATES OF AMERICA
    Date of birth / Date de naissance / Fecha de nacimiento
    15 MAR 1985
    Place of birth / Lieu de naissance / Lugar de nacimiento
    TEXAS, U.S.A.
    Date of issue / Date de délivrance / Fecha de expedición
    01 JAN 2020
    Date of expiration / Date d'expiration / Fecha de caducidad
    01 JAN 2030
    P<USASMITH<<JANE<MICHAEL<<<<<<<<<<<<<<<<<<<<
    P123456789USA8503150F3001015<<<<<<<<<<<<<<<0
    """

    func testParsesUSPassportFields() {
        let suggestions = PassportParser.suggestions(from: Self.sampleUSPassportOCRText)
        let byKey = Dictionary(uniqueKeysWithValues: suggestions.map { ($0.profileKey, $0.value) })

        XCTAssertEqual(byKey[ProfileFieldKey.displayName], "Jane Michael Smith")
        XCTAssertEqual(byKey[ProfileFieldKey.legalFirstName], "Jane")
        XCTAssertEqual(byKey[ProfileFieldKey.legalMiddleName], "Michael")
        XCTAssertEqual(byKey[ProfileFieldKey.legalLastName], "Smith")
        XCTAssertEqual(byKey[ProfileFieldKey.passportNumber], "P12345678")
        XCTAssertEqual(byKey[ProfileFieldKey.dateOfBirth], "03/15/1985")
        XCTAssertEqual(byKey[ProfileFieldKey.passportExpiry], "01/01/2030")
        XCTAssertEqual(byKey[ProfileFieldKey.passportCountry], "United States of America")
        XCTAssertEqual(byKey[ProfileFieldKey.country], "US")
        XCTAssertEqual(byKey[ProfileFieldKey.state], "TX")
    }

    func testOcrFieldSuggesterUsesPassportParser() {
        let suggestions = OcrFieldSuggester.suggest(from: Self.sampleUSPassportOCRText, documentType: .passport)
        let byKey = Dictionary(uniqueKeysWithValues: suggestions.map { ($0.profileKey, $0.value) })
        XCTAssertEqual(byKey[ProfileFieldKey.displayName], "Jane Michael Smith")
        XCTAssertEqual(byKey[ProfileFieldKey.passportNumber], "P12345678")
    }
}
