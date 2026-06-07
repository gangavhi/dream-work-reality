import XCTest
@testable import DreamWorkApp

final class UniversalDocumentParserTests: XCTestCase {
    func testExtractsSSNCardFieldsOnTwoLines() {
        let text = """
        SOCIAL SECURITY
        Jane
        Smith
        123-45-6789
        """

        let suggestions = UniversalDocumentParser.parse(from: text)
        let byKey = Dictionary(uniqueKeysWithValues: suggestions.map { ($0.profileKey, $0.value) })

        XCTAssertEqual(byKey[ProfileFieldKey.legalFirstName], "Jane")
        XCTAssertEqual(byKey[ProfileFieldKey.legalLastName], "Smith")
        XCTAssertEqual(byKey[ProfileFieldKey.displayName], "Jane Smith")
    }

    func testExtractsSSNCardFields() {
        let text = """
        SOCIAL SECURITY
        THIS NUMBER HAS BEEN ESTABLISHED FOR
        Jane Smith
        123-45-6789
        """

        let suggestions = UniversalDocumentParser.parse(from: text)
        let byKey = Dictionary(uniqueKeysWithValues: suggestions.map { ($0.profileKey, $0.value) })

        XCTAssertEqual(byKey[ProfileFieldKey.ssn], "123-45-6789")
        XCTAssertEqual(byKey[ProfileFieldKey.legalFirstName], "Jane")
        XCTAssertEqual(byKey[ProfileFieldKey.legalLastName], "Smith")
        XCTAssertEqual(byKey[ProfileFieldKey.displayName], "Jane Smith")
    }

    func testExtractsDOBFromLabeledLine() {
        let text = """
        Jane Smith
        DOB: 03/15/1985
        123-45-6789
        """

        let suggestions = UniversalDocumentParser.parse(from: text)
        let dob = suggestions.first(where: { $0.profileKey == ProfileFieldKey.dateOfBirth })?.value
        XCTAssertEqual(dob, "03/15/1985")
    }

    func testDoesNotBleedDriverLicenseParserOnDLKeywords() {
        let text = DriverLicenseParserTests.texasSampleOCRText
        let suggestions = UniversalDocumentParser.parse(from: text)
        let keys = Set(suggestions.map(\.profileKey))

        XCTAssertFalse(keys.contains(ProfileFieldKey.driversLicenseNumber))
        XCTAssertFalse(keys.contains(ProfileFieldKey.driversLicenseState))
    }

    func testEstimatedFieldsTagged() {
        let suggestions = UniversalDocumentParser.parse(from: "Jane Smith\n123-45-6789")
        XCTAssertTrue(suggestions.allSatisfy { $0.mappingSource == .estimated })
        XCTAssertTrue(suggestions.allSatisfy { $0.confidence == "Estimated" })
    }

    func testGarbledSSAStubUsesLayoutAwareNameNotHeaderGarbage() {
        let text = """
        03/15/2019
        123-45-6789
        THIS NUMBER HAS BEEN ESTABLISHED FOR
        LOCIAL SEOURTA
        LOCALSECURI
        YOUR SOCIAL SECURITY CARD
        ADULTS: Sign this card in ink immediately.
        Do not laminate.
        JANE DOE
        123 MAIN ST
        SPRINGFIELD IL 62704-1234
        """

        XCTAssertTrue(UniversalDocumentParser.looksLikeSSNDocument(text))
        let suggestions = UniversalDocumentParser.parse(from: text)
        let byKey = Dictionary(uniqueKeysWithValues: suggestions.map { ($0.profileKey, $0.value) })

        XCTAssertEqual(byKey[ProfileFieldKey.ssn], "123-45-6789")
        XCTAssertEqual(byKey[ProfileFieldKey.displayName], "Jane Doe")
        XCTAssertEqual(byKey[ProfileFieldKey.legalFirstName], "Jane")
        XCTAssertEqual(byKey[ProfileFieldKey.legalLastName], "Doe")
        XCTAssertEqual(byKey[ProfileFieldKey.addressLine1], "123 Main St")
        XCTAssertEqual(byKey[ProfileFieldKey.city], "Springfield")
        XCTAssertEqual(byKey[ProfileFieldKey.state], "IL")
        XCTAssertEqual(byKey[ProfileFieldKey.postalCode], "62704")
        XCTAssertNil(byKey[ProfileFieldKey.dateOfBirth], "Issue date on stub must not map to DOB")
        XCTAssertFalse(suggestions.contains { $0.value.localizedCaseInsensitiveContains("locial") })
    }

    /// Synthetic SSA card + mailing stub layout (card OCR block before address block).
    func testExtractsSSNCardWithMailingStubLayout() {
        let text = """
        SOCIAL SECURITY
        VALID FOR WORK ONLY WITH DHS AUTHORIZATION
        987-65-4321
        ALEX RIVERA
        03/15/2019
        YOUR SOCIAL SECURITY CARD
        ADULTS: Sign this card in ink immediately.
        Do not laminate.
        ALEX RIVERA
        742 OAK STREET
        AUSTIN TX 78701-1234
        """

        XCTAssertTrue(UniversalDocumentParser.looksLikeSSNDocument(text))
        let suggestions = UniversalDocumentParser.parse(from: text)
        let byKey = Dictionary(uniqueKeysWithValues: suggestions.map { ($0.profileKey, $0.value) })

        XCTAssertEqual(byKey[ProfileFieldKey.ssn], "987-65-4321")
        XCTAssertEqual(byKey[ProfileFieldKey.displayName], "Alex Rivera")
        XCTAssertEqual(byKey[ProfileFieldKey.legalFirstName], "Alex")
        XCTAssertEqual(byKey[ProfileFieldKey.legalLastName], "Rivera")
        XCTAssertEqual(byKey[ProfileFieldKey.addressLine1], "742 Oak Street")
        XCTAssertEqual(byKey[ProfileFieldKey.city], "Austin")
        XCTAssertEqual(byKey[ProfileFieldKey.state], "TX")
        XCTAssertEqual(byKey[ProfileFieldKey.postalCode], "78701")
        XCTAssertNil(byKey[ProfileFieldKey.dateOfBirth], "Card issue date must not map to DOB")
    }

    /// Card instruction boilerplate must not be mapped as person names (device repro).
    func testRejectsSSACardInstructionBoilerplateAsNames() {
        let text = """
        YOUR SOCIAL SECURITY CARD
        ADULTS: Sign this card in ink immediately.
        Children: Do Not Sign Until Age 18 Or Your First Job,
        Do not laminate.
        456-78-9012
        JANE DOE
        123 MAIN ST
        SPRINGFIELD IL 62704-1234
        """

        XCTAssertTrue(UniversalDocumentParser.looksLikeSSNDocument(text))
        let classification = DocumentTypeClassifier.classify(from: text)
        XCTAssertEqual(classification.documentType, .ssnCard)

        let suggestions = UniversalDocumentParser.parse(from: text)
        let byKey = Dictionary(uniqueKeysWithValues: suggestions.map { ($0.profileKey, $0.value) })

        XCTAssertEqual(byKey[ProfileFieldKey.ssn], "456-78-9012")
        XCTAssertEqual(byKey[ProfileFieldKey.legalFirstName], "Jane")
        XCTAssertEqual(byKey[ProfileFieldKey.legalLastName], "Doe")
        XCTAssertFalse(suggestions.contains { $0.value.localizedCaseInsensitiveContains("children:") })
        XCTAssertFalse(suggestions.contains { $0.value.localizedCaseInsensitiveContains("first job") })
    }

    func testClassifiesSSNCardFromInstructionBoilerplateWithoutSSNVisible() {
        let text = """
        YOUR SOCIAL SECURITY CARD
        Children: Do Not Sign Until Age 18 Or Your First Job,
        Do not laminate.
        """

        XCTAssertTrue(UniversalDocumentParser.looksLikeSSNDocument(text))
        let classification = DocumentTypeClassifier.classify(from: text)
        XCTAssertEqual(classification.documentType, .ssnCard)

        let suggestions = PersonNameResolver.apply(
            to: [],
            ocrText: text,
            documentType: classification.documentType
        )
        XCTAssertFalse(suggestions.contains { $0.profileKey == ProfileFieldKey.legalFirstName })
        XCTAssertFalse(suggestions.contains { $0.value.localizedCaseInsensitiveContains("children:") })
    }
}
