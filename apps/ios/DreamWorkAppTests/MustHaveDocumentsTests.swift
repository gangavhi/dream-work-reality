import XCTest
@testable import DreamWorkApp

final class MustHaveDocumentsTests: XCTestCase {
    // MARK: - Checklist completeness (all 9 ✓)

    func testAllNineCategoriesCompleteWithMockPersonAndStash() {
        let person = MustHaveDocumentMockFixtures.fullyPopulatedPerson()
        let stashed = MustHaveDocumentMockFixtures.allStashedTypes

        for category in MustHaveDocumentCategory.allCases {
            XCTAssertTrue(
                category.isComplete(person: person, stashedTypes: stashed),
                "Expected complete: \(category.rawValue)"
            )
        }
    }

    func testExpectedCategoryLabelsMatchUI() {
        XCTAssertEqual(
            MustHaveDocumentMockFixtures.expectedCategoryLabels,
            [
                "Passport / ID",
                "Driver License",
                "SSN Card",
                "Address Proof",
                "Insurance Card",
                "W-2 / 1099 / Pay stub",
                "Bank Statement",
                "Emergency Contact",
                "Employment Information",
            ]
        )
    }

    func testEachCategoryCompletesIndependently() {
        let base = PersonRecord.empty(id: "solo")

        XCTAssertTrue(
            MustHaveDocumentCategory.passportOrID.isComplete(
                person: base.withValue("P999", for: ProfileFieldKey.passportNumber),
                stashedTypes: []
            )
        )
        XCTAssertTrue(
            MustHaveDocumentCategory.driverLicense.isComplete(
                person: base.withValue("D999", for: ProfileFieldKey.driversLicenseNumber),
                stashedTypes: []
            )
        )
        XCTAssertTrue(
            MustHaveDocumentCategory.ssnCard.isComplete(
                person: base.withValue("123-45-6789", for: ProfileFieldKey.ssn),
                stashedTypes: []
            )
        )
        XCTAssertTrue(
            MustHaveDocumentCategory.addressProof.isComplete(
                person: base.withValue("100 Main", for: ProfileFieldKey.addressLine1),
                stashedTypes: []
            )
        )
        XCTAssertTrue(
            MustHaveDocumentCategory.insuranceCard.isComplete(
                person: base.withValue("MEM001", for: ProfileFieldKey.insuranceMemberId),
                stashedTypes: []
            )
        )
        XCTAssertTrue(
            MustHaveDocumentCategory.taxForms.isComplete(
                person: base,
                stashedTypes: ["form1099"]
            )
        )
        XCTAssertTrue(
            MustHaveDocumentCategory.bankStatement.isComplete(
                person: base.withValue("Test Bank", for: ProfileFieldKey.bankName),
                stashedTypes: []
            )
        )
        XCTAssertTrue(
            MustHaveDocumentCategory.emergencyContact.isComplete(
                person: base.withValue("Sam Helper", for: ProfileFieldKey.emergencyContactName),
                stashedTypes: []
            )
        )
        XCTAssertTrue(
            MustHaveDocumentCategory.employment.isComplete(
                person: base.withValue("Employer Inc", for: ProfileFieldKey.employerName),
                stashedTypes: []
            )
        )
    }

    // MARK: - Stash whitelist

    func testStashWhitelistCoversAllMandatoryUploadTypes() {
        let mandatoryStashTypes = [
            "passport", "stateId", "driversLicense", "ssnCard",
            "utility_bill", "lease", "insuranceCard",
            "w2", "form1099", "payStub", "bankStatement",
        ]
        for type in mandatoryStashTypes {
            XCTAssertTrue(RewriteStashPolicy.shouldStash(documentType: type), type)
        }
    }

    func testTaxDocumentsNotFormRelevantButStashed() {
        for type in ["w2", "form1099", "payStub"] {
            XCTAssertTrue(RewriteStashPolicy.shouldStash(documentType: type))
            XCTAssertFalse(RewriteStashPolicy.isFormRelevant(documentType: type))
        }
    }

    func testCanonicalTaxTypeDisambiguates1099FromW2() {
        XCTAssertEqual(
            RewriteStashPolicy.canonicalType(for: .taxDocument, ocrText: MustHaveDocumentMockFixtures.form1099OCR),
            "form1099"
        )
        XCTAssertEqual(
            RewriteStashPolicy.canonicalType(for: .taxDocument, ocrText: MustHaveDocumentMockFixtures.w2OCR),
            "w2"
        )
    }

    // MARK: - Mock OCR extraction per document

    func testMockPassportExtractsFields() {
        let suggestions = RewriteFieldExtractor.extract(
            from: MustHaveDocumentMockFixtures.passportOCR,
            documentType: .passport,
            machineReadable: MachineReadableFieldExtractor.Result(
                suggestions: [],
                decodedPayload: false,
                sources: []
            )
        )
        let keys = Set(suggestions.map(\.profileKey))
        XCTAssertTrue(keys.contains(ProfileFieldKey.passportNumber))
        XCTAssertTrue(keys.contains(ProfileFieldKey.legalFirstName))
    }

    func testMockDriverLicenseExtractsFields() {
        let suggestions = RewriteFieldExtractor.extract(
            from: MustHaveDocumentMockFixtures.driverLicenseOCR,
            documentType: .driversLicense,
            machineReadable: MachineReadableFieldExtractor.Result(
                suggestions: [],
                decodedPayload: false,
                sources: []
            )
        )
        XCTAssertTrue(suggestions.contains { $0.profileKey == ProfileFieldKey.driversLicenseNumber })
    }

    func testMockSSNCardExtractsSSN() {
        let suggestions = RewriteFieldExtractor.extract(
            from: MustHaveDocumentMockFixtures.ssnCardOCR,
            documentType: .ssnCard,
            machineReadable: MachineReadableFieldExtractor.Result(
                suggestions: [],
                decodedPayload: false,
                sources: []
            )
        )
        XCTAssertEqual(suggestions.first?.profileKey, ProfileFieldKey.ssn)
        XCTAssertEqual(suggestions.first?.value, "123-45-6789")
    }

    func testMockInsuranceCardExtractsMemberId() {
        let suggestions = RewriteFieldExtractor.extract(
            from: MustHaveDocumentMockFixtures.insuranceCardOCR,
            documentType: .insuranceCard,
            machineReadable: MachineReadableFieldExtractor.Result(
                suggestions: [],
                decodedPayload: false,
                sources: []
            )
        )
        XCTAssertTrue(suggestions.contains { $0.profileKey == ProfileFieldKey.insuranceMemberId })
    }

    func testMockUtilityBillExtractsAddress() {
        let suggestions = RewriteFieldExtractor.extract(
            from: MustHaveDocumentMockFixtures.utilityBillOCR,
            documentType: .utilityBill,
            machineReadable: MachineReadableFieldExtractor.Result(
                suggestions: [],
                decodedPayload: false,
                sources: []
            )
        )
        XCTAssertFalse(suggestions.isEmpty)
    }

    func testMockBankStatementExtractsBankName() {
        let suggestions = RewriteFieldExtractor.extract(
            from: MustHaveDocumentMockFixtures.bankStatementOCR,
            documentType: .bankStatement,
            machineReadable: MachineReadableFieldExtractor.Result(
                suggestions: [],
                decodedPayload: false,
                sources: []
            )
        )
        XCTAssertTrue(suggestions.contains { $0.profileKey == ProfileFieldKey.bankName })
    }

    func testMockTaxDocumentsDoNotExtractFieldsV1() {
        for (label, ocr) in [
            ("w2", MustHaveDocumentMockFixtures.w2OCR),
            ("1099", MustHaveDocumentMockFixtures.form1099OCR),
            ("paystub", MustHaveDocumentMockFixtures.payStubOCR),
        ] {
            let docType: ScannedDocumentType = label == "paystub" ? .employmentDocument : .taxDocument
            let suggestions = RewriteFieldExtractor.extract(
                from: ocr,
                documentType: docType,
                machineReadable: MachineReadableFieldExtractor.Result(
                suggestions: [],
                decodedPayload: false,
                sources: []
            )
            )
            XCTAssertTrue(suggestions.isEmpty, "Expected no extract for \(label) in v1")
        }
    }

    // MARK: - Profile vault metadata JSON shape

    func testProfileVaultMetadataMatchesContract() throws {
        let metadata = ProfileVaultMetadata(
            consents: .init(allowAutofill: true, allowDocumentScan: true),
            aliases: ["nickname", "previous name"],
            storedSignatures: [],
            uploadedFiles: [
                .init(
                    documentId: "doc-1",
                    documentType: "passport",
                    encryptedStoragePath: "submission_docs/person-mock/passport/current.enc",
                    checksum: "abc123",
                    createdAt: "2024-01-15T12:00:00Z"
                ),
            ]
        )

        let data = try JSONEncoder().encode(metadata)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        let consents = json?["consents"] as? [String: Any]
        XCTAssertEqual(consents?["allowAutofill"] as? Bool, true)
        XCTAssertEqual(consents?["allowDocumentScan"] as? Bool, true)
        XCTAssertEqual(json?["aliases"] as? [String], ["nickname", "previous name"])
        XCTAssertEqual(json?["storedSignatures"] as? [String], [])

        let files = json?["uploadedFiles"] as? [[String: Any]]
        XCTAssertEqual(files?.count, 1)
        XCTAssertEqual(files?.first?["documentType"] as? String, "passport")
        XCTAssertEqual(files?.first?["encryptedStoragePath"] as? String,
                       "submission_docs/person-mock/passport/current.enc")
    }

    // MARK: - Encrypted stash round-trip

    func testSubmissionDocumentStoreEncryptsAndDecryptsAllMandatoryTypes() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("must-have-stash-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }

        let store = SubmissionDocumentStore.makeForTesting(in: root)
        let person = MustHaveDocumentMockFixtures.fullyPopulatedPerson()
        let mandatoryTypes = [
            "passport", "driversLicense", "ssnCard", "utility_bill",
            "insuranceCard", "w2", "form1099", "payStub", "bankStatement",
        ]

        for docType in mandatoryTypes {
            let source = root.appendingPathComponent("source-\(docType).pdf")
            let payload = "mock-\(docType)-payload".data(using: .utf8)!
            try payload.write(to: source)

            let record = try store.save(
                personId: person.id,
                documentType: docType,
                sourceURL: source,
                personDisplayName: person.displayTitle
            )

            XCTAssertEqual(record.documentType, docType)
            XCTAssertTrue(record.filePath.hasSuffix("current.enc"))

            let decrypted = try store.decryptCurrent(personId: person.id, documentType: docType)
            XCTAssertEqual(decrypted, payload)
        }

        let metadata = MustHaveDocumentMockFixtures.vaultMetadata(from: store.currentRecords(personId: person.id))
        XCTAssertEqual(metadata.uploadedFiles.count, mandatoryTypes.count)
        XCTAssertTrue(metadata.consents.allowAutofill)
        XCTAssertTrue(metadata.consents.allowDocumentScan)

        let stashed = store.stashedDocumentTypes(personId: person.id)
        for category in MustHaveDocumentCategory.allCases {
            XCTAssertTrue(
                category.isComplete(person: person, stashedTypes: stashed),
                "After stash, expected complete: \(category.rawValue)"
            )
        }
    }
}
