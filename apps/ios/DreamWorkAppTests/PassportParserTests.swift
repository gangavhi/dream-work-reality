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

    /// Label-only OCR noise (duplicate headers, no values on next line) must not become profile fields.
    static let sampleUSPassportLabelNoiseOCRText = """
    UNITED STATES OF AMERICA
    PASSPORT
    Given Names
    Given Names
    Place of Birth
    Piace Of Birth
    Passport No.
    A18191851
    Nationality
    United States of America
    Date of issue
    03/24/2023
    Date of expiration
    07/20/2028
    P<USASMITH<<JANE<MICHAEL<<<<<<<<<<<<<<<<<<<<
    A181918510USA8503159F2807205<<<<<<<<<<<<<<<0
    """

    /// Biodata-only OCR (no MRZ lines) — matches common Simulator scan failures.
    static let sampleUSPassportBiodataOnlyOCRText = """
    UNITED STATES OF AMERICA
    PASSPORT
    Given Names
    Given Names
    Place of Birth
    Piace Of Birth
    Passport No.
    A18191851
    Nationality
    United States of America
    Date of issue
    03/24/2023
    Date of expiration
    07/20/2028
    """

    func testRejectsUSPassportBiodataOnlyLabelNoise() {
        let suggestions = PassportParser.suggestions(from: Self.sampleUSPassportBiodataOnlyOCRText)
        let byKey = Dictionary(uniqueKeysWithValues: suggestions.map { ($0.profileKey, $0.value) })

        XCTAssertEqual(byKey[ProfileFieldKey.passportNumber], "A18191851")
        XCTAssertEqual(
            byKey[ProfileFieldKey.passportCountry]?.lowercased(),
            "united states of america"
        )
        XCTAssertEqual(byKey[ProfileFieldKey.passportExpiry], "07/20/2028")
        XCTAssertEqual(byKey[ProfileFieldKey.country], "US")
        XCTAssertNil(byKey[ProfileFieldKey.legalFirstName])
        XCTAssertNil(byKey[ProfileFieldKey.legalMiddleName])
        XCTAssertNil(byKey[ProfileFieldKey.displayName])
        XCTAssertNil(byKey[ProfileFieldKey.city])
        XCTAssertNil(byKey[ProfileFieldKey.dateOfBirth], "issue date must not become DOB")
    }

    func testPersonNameResolverRejectsUSPassportBiodataOnlyLabelNoise() {
        let resolved = PersonNameResolver.apply(
            to: [],
            ocrText: Self.sampleUSPassportBiodataOnlyOCRText,
            documentType: .passport
        )
        let byKey = Dictionary(uniqueKeysWithValues: resolved.map { ($0.profileKey, $0.value) })
        XCTAssertEqual(byKey[ProfileFieldKey.passportNumber], "A18191851")
        XCTAssertNil(byKey[ProfileFieldKey.legalFirstName])
        XCTAssertNil(byKey[ProfileFieldKey.city])
        XCTAssertNil(byKey[ProfileFieldKey.dateOfBirth])
    }

    func testRejectsUSPassportLabelNoiseAsFieldValues() {
        let suggestions = PassportParser.suggestions(from: Self.sampleUSPassportLabelNoiseOCRText)
        let byKey = Dictionary(uniqueKeysWithValues: suggestions.map { ($0.profileKey, $0.value) })

        XCTAssertNotEqual(byKey[ProfileFieldKey.legalFirstName], "Given")
        XCTAssertNotEqual(byKey[ProfileFieldKey.legalMiddleName], "Names")
        XCTAssertNotEqual(byKey[ProfileFieldKey.displayName], "Given Names")
        XCTAssertNil(byKey[ProfileFieldKey.city], "place-of-birth labels must not map to address city")
        XCTAssertEqual(byKey[ProfileFieldKey.legalFirstName], "Jane")
        XCTAssertEqual(byKey[ProfileFieldKey.legalLastName], "Smith")
        XCTAssertEqual(byKey[ProfileFieldKey.passportNumber], "A18191851")
        XCTAssertEqual(byKey[ProfileFieldKey.dateOfBirth], "03/15/1985")
        XCTAssertNotEqual(byKey[ProfileFieldKey.dateOfBirth], "03/24/2023")
        XCTAssertEqual(byKey[ProfileFieldKey.passportExpiry], "07/20/2028")
    }
}
