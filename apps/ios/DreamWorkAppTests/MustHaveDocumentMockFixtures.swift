import Foundation
@testable import DreamWorkApp

/// Synthetic OCR + profile data for all 9 must-have household document categories.
enum MustHaveDocumentMockFixtures {
    static let personId = "person-mock-household"

    static let passportOCR = PassportParserTests.sampleUSPassportOCRText

    static let driverLicenseOCR = DriverLicenseParserTests.texasSampleOCRText

    static let stateIdOCR = """
    STATE ID
    IDENTIFICATION CARD
    NON-DRIVER
    1. RIVERA
    2. ALEX
    ID: S98765432
    DOB: 06/12/1992
    EXP: 06/12/2028
    """

    static let ssnCardOCR = """
    SOCIAL SECURITY
    THIS NUMBER HAS BEEN ESTABLISHED FOR
    ALEX RIVERA
    123-45-6789
    """

    static let utilityBillOCR = """
    AUSTIN ELECTRIC UTILITY
    BILLING STATEMENT
    SERVICE ADDRESS
    742 OAK STREET
    AUSTIN TX 78701
    """

    static let insuranceCardOCR = """
    BLUE CROSS SHIELD INSURANCE
    MEMBER ID: ABC123456789
    GROUP #: GRP001
    SUBSCRIBER: ALEX RIVERA
    """

    static let w2OCR = """
    IRS W-2 WAGE AND TAX STATEMENT
    TAX YEAR 2024
    EMPLOYER'S NAME: ACME CORP
    """

    static let form1099OCR = """
    IRS FORM 1099-MISC
    TAX YEAR 2024
    PAYER: FREELANCE CLIENT LLC
    """

    static let payStubOCR = """
    PAY STUB
    EMPLOYER: ACME CORP
    EARNINGS STATEMENT
    PAY PERIOD END 03/15/2024
    """

    static let bankStatementOCR = """
    FIRST NATIONAL BANK
    BANK STATEMENT
    ACCOUNT STATEMENT
    ROUTING 111000025
    ACCOUNT ****1234
    """

    /// Person with extracted fields for every must-have category.
    static func fullyPopulatedPerson() -> PersonRecord {
        var person = PersonRecord.empty(id: personId)
        let fields: [String: String] = [
            ProfileFieldKey.displayName: "Alex Rivera",
            ProfileFieldKey.passportNumber: "P12345678",
            ProfileFieldKey.driversLicenseNumber: "D12345678",
            ProfileFieldKey.ssn: "123-45-6789",
            ProfileFieldKey.addressLine1: "742 OAK STREET",
            ProfileFieldKey.city: "AUSTIN",
            ProfileFieldKey.insuranceMemberId: "ABC123456789",
            ProfileFieldKey.bankName: "FIRST NATIONAL BANK",
            ProfileFieldKey.emergencyContactName: "Jordan Rivera",
            ProfileFieldKey.emergencyContactPhone: "512-555-0100",
            ProfileFieldKey.employerName: "ACME CORP",
        ]
        return person.merged(with: fields)
    }

    /// Stash types covering tax trio + lease for address proof variety.
    static let allStashedTypes: Set<String> = [
        "passport", "driversLicense", "ssnCard", "utility_bill", "lease",
        "insuranceCard", "w2", "form1099", "payStub", "bankStatement",
    ]

    static let expectedCategoryLabels: [String] = MustHaveDocumentCategory.allCases.map(\.rawValue)

    static func vaultMetadata(from records: [SubmissionDocumentStore.Record]) -> ProfileVaultMetadata {
        ProfileVaultMetadata(
            consents: .init(allowAutofill: true, allowDocumentScan: true),
            aliases: ["nickname", "previous name"],
            storedSignatures: [],
            uploadedFiles: ProfileVaultMetadata.uploadedFiles(from: records)
        )
    }
}
