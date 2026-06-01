import XCTest
@testable import DreamWorkApp

final class DocumentUnderstandingServiceTests: XCTestCase {
    func testLocalClassifierDetectsDriversLicenseFromKeywords() {
        let result = LocalDocumentClassifier.classify(
            layoutText: "TEXAS DRIVER LICENSE\n1. SMITH\n2. JOHN",
            modelInput: "TEXAS DRIVER LICENSE",
            payloadHints: .empty,
            allowHeavyLLM: false
        )
        XCTAssertEqual(result.openDocumentType, "drivers_license")
        XCTAssertTrue(result.runtimeStatus.hasPrefix("classifier_active:"))
    }

    func testLocalClassifierDetectsPassportFromMRZ() {
        let hints = EmbeddedPayloadHints.Result(
            barcodePayloads: [],
            mrzLines: ["P<USASMITH<<JOHN<<<<<<<<<<<<<<<<<<<<<<<<<<<"]
        )
        let result = LocalDocumentClassifier.classify(
            layoutText: "",
            modelInput: "",
            payloadHints: hints,
            allowHeavyLLM: false
        )
        XCTAssertEqual(result.openDocumentType, "passport")
        XCTAssertEqual(result.runtimeStatus, "classifier_active:mrz")
    }

    func testFieldNormalizationStandardizesDateAndName() {
        let raw = OcrFieldSuggestion(
            profileKey: ProfileFieldKey.dateOfBirth,
            label: "DOB",
            value: "03/15/1985",
            confidence: "Medium",
            confidenceScore: 0.72,
            mappingSource: .onDevice
        )
        let normalized = FieldNormalizationEngine.normalizeField(raw)
        XCTAssertEqual(normalized.value, "1985-03-15")

        let name = FieldNormalizationEngine.normalizeName("jane MARIE smith")
        XCTAssertEqual(name, "Jane MARIE Smith")
    }

    func testSchemaMappingProducesDrivingLicenseJSONShape() {
        let suggestions = [
            OcrFieldSuggestion(
                profileKey: ProfileFieldKey.legalFirstName,
                label: "First",
                value: "Jane",
                confidence: "High",
                confidenceScore: 0.9,
                mappingSource: .barcode
            ),
            OcrFieldSuggestion(
                profileKey: ProfileFieldKey.legalLastName,
                label: "Last",
                value: "Smith",
                confidence: "High",
                confidenceScore: 0.9,
                mappingSource: .barcode
            ),
            OcrFieldSuggestion(
                profileKey: ProfileFieldKey.driversLicenseNumber,
                label: "DL#",
                value: "12345678",
                confidence: "High",
                confidenceScore: 0.95,
                mappingSource: .barcode
            ),
            OcrFieldSuggestion(
                profileKey: ProfileFieldKey.addressLine1,
                label: "Address",
                value: "742 Oak Street",
                confidence: "Medium",
                confidenceScore: 0.75,
                mappingSource: .onDevice
            ),
            OcrFieldSuggestion(
                profileKey: ProfileFieldKey.city,
                label: "City",
                value: "Austin",
                confidence: "Medium",
                confidenceScore: 0.75,
                mappingSource: .onDevice
            ),
            OcrFieldSuggestion(
                profileKey: ProfileFieldKey.state,
                label: "State",
                value: "TX",
                confidence: "Medium",
                confidenceScore: 0.75,
                mappingSource: .onDevice
            ),
            OcrFieldSuggestion(
                profileKey: ProfileFieldKey.postalCode,
                label: "ZIP",
                value: "78701",
                confidence: "Medium",
                confidenceScore: 0.75,
                mappingSource: .onDevice
            ),
        ]

        let output = SchemaMappingEngine.map(openDocumentType: "drivers_license", suggestions: suggestions)
        XCTAssertEqual(output.documentType, "drivers_license")
        XCTAssertEqual(fieldValue("first_name", in: output), "Jane")
        XCTAssertEqual(fieldValue("last_name", in: output), "Smith")
        XCTAssertEqual(fieldValue("license_number", in: output), "12345678")
        XCTAssertTrue(fieldValue("address", in: output).contains("742 Oak Street"))
        XCTAssertTrue(fieldValue("address", in: output).contains("78701"))
    }

    func testProfileMergePrefersBarcodeOverExisting() {
        let existing = PersonRecord(
            id: "person-1",
            fields: [
                .init(key: ProfileFieldKey.legalFirstName, value: "Jon"),
                .init(key: ProfileFieldKey.driversLicenseNumber, value: "OLD123"),
            ]
        )
        let suggestions = [
            OcrFieldSuggestion(
                profileKey: ProfileFieldKey.driversLicenseNumber,
                label: "DL#",
                value: "NEW456",
                confidence: "High",
                confidenceScore: 0.96,
                mappingSource: .barcode
            ),
        ]
        let merged = ProfileMergeEngine.merge(
            existing: existing,
            suggestions: suggestions,
            documentType: "drivers_license"
        )
        XCTAssertEqual(merged.person.value(for: ProfileFieldKey.driversLicenseNumber), "NEW456")
        XCTAssertEqual(merged.person.value(for: ProfileFieldKey.legalFirstName), "Jon")
    }

    func testConfidenceOrchestratorFlagsLowConfidenceFields() {
        let suggestion = OcrFieldSuggestion(
            profileKey: ProfileFieldKey.displayName,
            label: "Name",
            value: "X",
            confidence: "Estimated",
            confidenceScore: 0.4,
            mappingSource: .estimated
        )
        let enriched = ConfidenceOrchestrator.enrich(
            [suggestion],
            documentType: .other,
            ocrCorpus: "unrelated text",
            averageOCRBlockConfidence: 0.5
        )
        XCTAssertTrue(enriched.first?.requiresManualConfirmation ?? false)
    }

    func testDocumentSchemaKeysForInsurance() {
        let keys = ProfileSchemaKeysForDocument.keys(forOpenDocumentType: "insurance_card", fallbackToAll: false)
        XCTAssertTrue(keys.contains(ProfileFieldKey.insuranceMemberId))
        XCTAssertFalse(keys.contains(ProfileFieldKey.passportNumber))
    }

    private func fieldValue(
        _ key: String,
        in output: SchemaMappingEngine.StandardizedDocumentOutput
    ) -> String {
        output.fields.first { $0.key == key }?.value ?? ""
    }
}
