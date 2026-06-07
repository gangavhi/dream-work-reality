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
    PUNE, MAHARASHTRA
    MUMBAI
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

    /// Synthetic multi-page Indian passport OCR (biodata + address); no real PII.
    static let sampleMultiPageNoisyIndianPassportOCRText = """
    REPUBLIC OF INDIA
    Passport~do
    PATEL
    AMIT.0
    INDIAN
    02ID6/1990
    PUNE, MAHARASHTRA
    MUMBAI
    27/12/2014
    26./.12/24.24
    M49kQ123<6INDp~QQfaQ
    M G ROAD, SHIVAJI NAGAR
    WHITEFIELD, BANGALORE
    PIN:411028, MAHARASHTRA, INDIA
    PATEL
    AMITKUMAR
    M4940123 M 02JUN1990 IND
    """

    func testParsesMultiPageNoisyIndianPassportFromUpload() {
        let suggestions = IndianPassportParser.suggestions(from: Self.sampleMultiPageNoisyIndianPassportOCRText)
        let byKey = Dictionary(uniqueKeysWithValues: suggestions.map { ($0.profileKey, $0.value) })

        XCTAssertEqual(byKey[ProfileFieldKey.legalFirstName], "Amitkumar")
        XCTAssertEqual(byKey[ProfileFieldKey.legalLastName], "Patel")
        XCTAssertEqual(byKey[ProfileFieldKey.displayName], "Amitkumar Patel")
        XCTAssertEqual(byKey[ProfileFieldKey.passportNumber], "N4940123")
        XCTAssertEqual(byKey[ProfileFieldKey.dateOfBirth], "02/06/1990")
        XCTAssertEqual(byKey[ProfileFieldKey.passportIssueDate], "27/12/2014")
        XCTAssertEqual(byKey[ProfileFieldKey.passportExpiry], "26/12/2024")
        XCTAssertEqual(byKey[ProfileFieldKey.passportIssuedPlace], "Mumbai")
        XCTAssertNotNil(byKey[ProfileFieldKey.passportAddress])
        XCTAssertTrue(byKey[ProfileFieldKey.passportAddress]?.uppercased().contains("SHIVAJI") == true)
        XCTAssertEqual(byKey[ProfileFieldKey.postalCode], "411028")
    }

    static let sampleIndianPassportLabelNoiseOCRText = """
    REPUBLIC OF INDIA
    Given Name(s)
    Given Name(s)
    Surname
    PATEL
    Place of Birth
    Place of Birth
    PUNE, MAHARASHTRA
    Passport No. M1234567
    Date of Birth 15/03/1985
    P<INDPATEL<<AMIT<<<<<<<<<<<<<<<<<<<<<<<<<
    M1234567<0IND8503150M3001015<<<<<<<<<<<<<<04
    """

    /// Minimal vertical-stack biodata (no PASSPORT header) — matches spatial OCR layout tests.
    static let sampleIndianPassportSpatialStackOCRText = """
    Surname
    PATEL
    Given Name(s)
    PRIYA
    Date of Birth
    15/03/1990
    Nationality
    INDIAN
    """

    func testParsesIndianPassportSpatialStackBiodata() {
        let suggestions = IndianPassportParser.suggestions(from: Self.sampleIndianPassportSpatialStackOCRText)
        let byKey = Dictionary(uniqueKeysWithValues: suggestions.map { ($0.profileKey, $0.value) })
        XCTAssertEqual(byKey[ProfileFieldKey.legalLastName], "Patel")
        XCTAssertEqual(byKey[ProfileFieldKey.legalFirstName], "Priya")
        XCTAssertEqual(byKey[ProfileFieldKey.dateOfBirth], "15/03/1990")
    }

    func testRejectsIndianPassportLabelNoiseAsFieldValues() {
        let suggestions = IndianPassportParser.suggestions(from: Self.sampleIndianPassportLabelNoiseOCRText)
        let byKey = Dictionary(uniqueKeysWithValues: suggestions.map { ($0.profileKey, $0.value) })

        XCTAssertNotEqual(byKey[ProfileFieldKey.legalFirstName], "Given")
        XCTAssertNotEqual(byKey[ProfileFieldKey.legalMiddleName], "Names")
        XCTAssertEqual(byKey[ProfileFieldKey.legalFirstName], "Amit")
        XCTAssertEqual(byKey[ProfileFieldKey.legalLastName], "Patel")
        XCTAssertNotEqual(byKey[ProfileFieldKey.city]?.lowercased(), "place of birth")
    }

    /// Synthetic noisy multi-page scan (biodata + garbled back page); no real PII.
    static let sampleNoisyIndianPassportMegiaOCRText = """
    REPUBLIC OF INDIA
    Surname
    JAVIARA
    Given Name(s)
    MEGIA
    Date of Birth 19/07/1981
    P1234567
    P<INDJAVIARA<<MEGIA<<<<<<<<<<<<<<<<<<<<<<<<<<<
    P1234567<6IND8107199F2807205<<<<<<<<<<<<<<04
    R X0101 ~ A ~~~~~ ~fi~~,r3} Andhra, Pradesh, Chennai Name Of Spouse Kavali 2016327705007
    PIN:560001, ANDHRA PRADESH, INDIA
    """

    func testRejectsNoisyIndianPassportAddressBlobAndFixesDOBYear() {
        let suggestions = IndianPassportParser.suggestions(from: Self.sampleNoisyIndianPassportMegiaOCRText)
        let byKey = Dictionary(uniqueKeysWithValues: suggestions.map { ($0.profileKey, $0.value) })

        XCTAssertEqual(byKey[ProfileFieldKey.legalFirstName], "Megia")
        XCTAssertEqual(byKey[ProfileFieldKey.legalLastName], "Javiara")
        XCTAssertEqual(byKey[ProfileFieldKey.dateOfBirth], "19/07/1981")
        XCTAssertNotEqual(byKey[ProfileFieldKey.dateOfBirth], "07/19/0181")
        XCTAssertEqual(byKey[ProfileFieldKey.postalCode], "560001")
        XCTAssertEqual(byKey[ProfileFieldKey.state], "Andhra Pradesh")
        XCTAssertEqual(byKey[ProfileFieldKey.city], "Kavali")

        if let address = byKey[ProfileFieldKey.addressLine1] {
            XCTAssertFalse(address.contains("~"), "address must not contain OCR noise characters")
            XCTAssertLessThanOrEqual(address.count, 90)
        }
    }

    func testFixesOCRDOBYear0181To1981() {
        let text = """
        REPUBLIC OF INDIA
        Surname JAVIARA
        Given Name(s) MEGIA
        Date of Birth 07/19/0181
        P<INDJAVIARA<<MEGIA<<<<<<<<<<<<<<<<<<<<<<<<<<<
        P1234567<6IND8107199F2807205<<<<<<<<<<<<<<04
        """
        let suggestions = IndianPassportParser.suggestions(from: text)
        let dob = suggestions.first(where: { $0.profileKey == ProfileFieldKey.dateOfBirth })?.value
        XCTAssertEqual(dob, "19/07/1981")
    }

    func testPersonNameResolverRejectsPureIndianPassportOCRNoise() {
        let text = """
        REPUBLIC OF INDIA
        PASSPORT
        ..._.;~,V , _ .. : .;.;i.;~ M A ,e Ap, A L L L . , __t N D H ~!:_ , . .,.,ff-- -mer....-=. _,is Z
        """
        let result = PersonNameResolver.apply(to: [], ocrText: text, documentType: .passport)
        let nameKeys: Set<String> = [
            ProfileFieldKey.displayName,
            ProfileFieldKey.legalFirstName,
            ProfileFieldKey.legalMiddleName,
            ProfileFieldKey.legalLastName,
        ]
        XCTAssertTrue(result.filter { nameKeys.contains($0.profileKey) }.isEmpty)
    }

    func testRewriteFieldExtractorRoutesMultiPageIndianPassport() {
        let suggestions = RewriteFieldExtractor.extract(
            from: Self.sampleMultiPageNoisyIndianPassportOCRText,
            documentType: .passport,
            machineReadable: MachineReadableFieldExtractor.Result(
                suggestions: [],
                decodedPayload: false,
                sources: []
            )
        )
        let byKey = Dictionary(uniqueKeysWithValues: suggestions.map { ($0.profileKey, $0.value) })
        XCTAssertEqual(byKey[ProfileFieldKey.displayName], "Amitkumar Patel")
        XCTAssertEqual(byKey[ProfileFieldKey.passportNumber], "N4940123")
    }
}
