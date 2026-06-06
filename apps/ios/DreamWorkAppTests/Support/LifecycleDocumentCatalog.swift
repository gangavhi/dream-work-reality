import Foundation
@testable import DreamWorkApp

/// Major personal & household documents across a typical life cycle (synthetic OCR only — no real PII).
enum LifecycleDocumentCatalog {
    enum LifeStage: String, CaseIterable {
        case birthAndIdentity = "Birth & identity"
        case youthAndEducation = "Youth & education"
        case drivingAndTravel = "Driving & travel"
        case household = "Household & residency"
        case employmentAndTax = "Employment & tax"
        case health = "Health & benefits"
        case legalAndFamily = "Legal & family"
    }

    struct Spec: Identifiable {
        let id: String
        let lifeStage: LifeStage
        let title: String
        let expectedType: ScannedDocumentType
        /// Bundle image resource (without extension). When set, Vision OCR runs on the PNG fixture.
        let bundleImageBaseName: String?
        /// Synthetic OCR lines rendered to PNG when no bundle image is provided.
        let syntheticOCRLines: [String]
        /// Profile keys the pipeline should populate for this document category.
        let requiredProfileKeys: [String]
        /// Optional field validators `(profileKey, value) -> Bool`.
        let fieldChecks: [(String, (String) -> Bool)]
    }

    static let all: [Spec] = [
        // MARK: Birth & identity
        Spec(
            id: "birth_certificate",
            lifeStage: .birthAndIdentity,
            title: "Birth certificate",
            expectedType: .other,
            bundleImageBaseName: nil,
            syntheticOCRLines: [
                "CERTIFICATE OF LIVE BIRTH",
                "BUREAU OF VITAL STATISTICS",
                "NAME: JANE MARIE DOE",
                "DATE OF BIRTH: 03/15/1985",
                "SEX: F",
            ],
            requiredProfileKeys: [ProfileFieldKey.displayName, ProfileFieldKey.dateOfBirth],
            fieldChecks: [
                (ProfileFieldKey.displayName, { $0.localizedCaseInsensitiveContains("jane") }),
                (ProfileFieldKey.dateOfBirth, { $0.contains("1985") || $0.contains("03/15") }),
            ]
        ),
        Spec(
            id: "social_security_card",
            lifeStage: .birthAndIdentity,
            title: "Social Security card",
            expectedType: .ssnCard,
            bundleImageBaseName: nil,
            syntheticOCRLines: [
                "YOUR SOCIAL SECURITY CARD",
                "THIS NUMBER HAS BEEN ESTABLISHED FOR",
                "JANE DOE",
                "123-45-6789",
                "123 MAIN ST",
                "SPRINGFIELD IL 62704-1234",
            ],
            requiredProfileKeys: [ProfileFieldKey.ssn, ProfileFieldKey.displayName],
            fieldChecks: [
                (ProfileFieldKey.ssn, { $0 == "123-45-6789" }),
                (ProfileFieldKey.displayName, { $0.localizedCaseInsensitiveContains("jane") }),
            ]
        ),

        // MARK: Youth & education
        Spec(
            id: "state_id",
            lifeStage: .youthAndEducation,
            title: "State identification card",
            expectedType: .stateId,
            bundleImageBaseName: nil,
            syntheticOCRLines: [
                "OREGON",
                "IDENTIFICATION CARD",
                "STATE ID",
                "NON-DRIVER IDENTIFICATION",
                "NAME: JANE DOE",
                "ID: 987654321",
                "DOB: 03/15/1985",
                "100 MAIN ST",
                "PORTLAND OR 97201",
            ],
            requiredProfileKeys: [
                ProfileFieldKey.displayName, ProfileFieldKey.dateOfBirth, ProfileFieldKey.stateIdNumber,
            ],
            fieldChecks: [
                (ProfileFieldKey.legalLastName, { $0.localizedCaseInsensitiveContains("doe") }),
                (ProfileFieldKey.postalCode, { $0.contains("97201") }),
            ]
        ),

        // MARK: Driving & travel
        Spec(
            id: "drivers_license",
            lifeStage: .drivingAndTravel,
            title: "Driver's license",
            expectedType: .driversLicense,
            bundleImageBaseName: "texas-driver-license-sample",
            syntheticOCRLines: DriverLicenseParserTests.texasSampleOCRText
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty },
            requiredProfileKeys: [
                ProfileFieldKey.displayName, ProfileFieldKey.driversLicenseNumber, ProfileFieldKey.dateOfBirth,
            ],
            fieldChecks: [
                (ProfileFieldKey.driversLicenseState, { $0 == "TX" }),
                (ProfileFieldKey.displayName, { $0.localizedCaseInsensitiveContains("jane") }),
            ]
        ),
        Spec(
            id: "passport",
            lifeStage: .drivingAndTravel,
            title: "Passport",
            expectedType: .passport,
            bundleImageBaseName: "sample-document",
            syntheticOCRLines: [
                "UNITED STATES OF AMERICA",
                "PASSPORT",
                "Surname SMITH",
                "Given Names JANE MARIE",
                "Nationality UNITED STATES OF AMERICA",
                "Date of Birth 15 MAR 1985",
                "Passport No. 123456789",
            ],
            requiredProfileKeys: [ProfileFieldKey.displayName, ProfileFieldKey.passportNumber],
            fieldChecks: [
                (ProfileFieldKey.passportNumber, { $0.contains("123456789") }),
            ]
        ),

        // MARK: Household & residency
        Spec(
            id: "utility_bill",
            lifeStage: .household,
            title: "Utility bill",
            expectedType: .utilityBill,
            bundleImageBaseName: nil,
            syntheticOCRLines: [
                "CITY OF AUSTIN ELECTRIC UTILITY",
                "Account Number: 1234567890",
                "Service Address:",
                "JANE DOE",
                "100 MAIN STREET",
                "AUSTIN TX 78701",
                "Amount Due: $125.00",
            ],
            requiredProfileKeys: [ProfileFieldKey.postalCode, ProfileFieldKey.utilityProvider],
            fieldChecks: [
                (ProfileFieldKey.utilityProvider, { $0.localizedCaseInsensitiveContains("austin") || $0.localizedCaseInsensitiveContains("electric") }),
                (ProfileFieldKey.city, { $0.localizedCaseInsensitiveContains("austin") }),
            ]
        ),
        Spec(
            id: "bank_statement",
            lifeStage: .household,
            title: "Bank statement",
            expectedType: .bankStatement,
            bundleImageBaseName: nil,
            syntheticOCRLines: [
                "FIRST NATIONAL BANK",
                "ACCOUNT STATEMENT",
                "STATEMENT DATE: 01/31/2025",
                "ACCOUNT BALANCE: $1,234.56",
                "ROUTING NUMBER: 021000021",
                "JANE DOE",
                "100 MAIN ST",
                "AUSTIN TX 78701",
                "Account ending in 4321",
            ],
            requiredProfileKeys: [ProfileFieldKey.bankName, ProfileFieldKey.postalCode],
            fieldChecks: [
                (ProfileFieldKey.bankName, { $0.localizedCaseInsensitiveContains("bank") }),
                (ProfileFieldKey.bankAccountLast4, { $0 == "4321" }),
            ]
        ),

        // MARK: Employment & tax
        Spec(
            id: "pay_stub",
            lifeStage: .employmentAndTax,
            title: "Pay stub",
            expectedType: .employmentDocument,
            bundleImageBaseName: nil,
            syntheticOCRLines: [
                "ACME CORPORATION",
                "PAY STUB",
                "Employee: JANE DOE",
                "Employer: ACME CORPORATION",
                "Pay Date: 01/15/2025",
                "100 INDUSTRIAL BLVD",
                "AUSTIN TX 78701",
            ],
            requiredProfileKeys: [ProfileFieldKey.employerName],
            fieldChecks: [
                (ProfileFieldKey.employerName, { $0.localizedCaseInsensitiveContains("acme") }),
            ]
        ),
        Spec(
            id: "w2_tax",
            lifeStage: .employmentAndTax,
            title: "W-2 tax form",
            expectedType: .taxDocument,
            bundleImageBaseName: nil,
            syntheticOCRLines: [
                "Form W-2 Wage and Tax Statement",
                "2024",
                "Employer's name: ACME CORPORATION",
                "Employee's name: JANE DOE",
                "Employee's SSA number: 123-45-6789",
                "c Employer identification number 12-3456789",
            ],
            requiredProfileKeys: [ProfileFieldKey.taxFormType, ProfileFieldKey.employerName, ProfileFieldKey.taxYear],
            fieldChecks: [
                (ProfileFieldKey.taxFormType, { $0.localizedCaseInsensitiveContains("w-2") || $0.localizedCaseInsensitiveContains("w2") }),
                (ProfileFieldKey.taxYear, { $0 == "2024" }),
            ]
        ),

        // MARK: Health & benefits
        Spec(
            id: "insurance_card",
            lifeStage: .health,
            title: "Health insurance card",
            expectedType: .insuranceCard,
            bundleImageBaseName: nil,
            syntheticOCRLines: [
                "BLUE CROSS BLUE SHIELD",
                "MEMBER ID: XYZ987654321",
                "SUBSCRIBER: JANE DOE",
                "GROUP #: 12345",
                "DOB: 03/15/1985",
                "PLAN: PPO",
            ],
            requiredProfileKeys: [ProfileFieldKey.insuranceMemberId, ProfileFieldKey.insuranceCarrier],
            fieldChecks: [
                (ProfileFieldKey.insuranceMemberId, { $0.contains("987654321") || $0.contains("XYZ") }),
                (ProfileFieldKey.insuranceCarrier, { $0.localizedCaseInsensitiveContains("blue") || $0.localizedCaseInsensitiveContains("shield") }),
            ]
        ),

        // MARK: Legal & family
        Spec(
            id: "marriage_certificate",
            lifeStage: .legalAndFamily,
            title: "Marriage certificate",
            expectedType: .other,
            bundleImageBaseName: nil,
            syntheticOCRLines: [
                "CERTIFICATE OF MARRIAGE",
                "COUNTY CLERK — TRAVIS COUNTY",
                "PARTY A: JANE DOE",
                "PARTY B: JOHN SMITH",
                "DATE OF MARRIAGE: 06/01/2010",
            ],
            requiredProfileKeys: [ProfileFieldKey.displayName],
            fieldChecks: [
                (ProfileFieldKey.displayName, { $0.localizedCaseInsensitiveContains("jane") || $0.localizedCaseInsensitiveContains("doe") }),
            ]
        ),
    ]

    static func specs(in stage: LifeStage) -> [Spec] {
        all.filter { $0.lifeStage == stage }
    }
}
