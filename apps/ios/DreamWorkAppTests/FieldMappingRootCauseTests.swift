import XCTest
@testable import DreamWorkApp

/// Reproduces field-mapping failures seen on device when OCR raw text is correct.
final class FieldMappingRootCauseTests: XCTestCase {
    private var previousProvider: GenAISettings.Provider!

    override func setUp() {
        super.setUp()
        previousProvider = GenAISettings.provider
        GenAISettings.provider = .appleNative
    }

    override func tearDown() {
        GenAISettings.provider = previousProvider
        super.tearDown()
    }

    func testPassportSpatialBlocksMislabelSingleWordValuesAsLabels() async {
        // Typical passport OCR: label row then value row (vertical stack).
        let doc = verticalBlocks([
            ("Surname", 0.72),
            ("SHARMA", 0.68),
            ("Given Name(s)", 0.62),
            ("PRIYA", 0.58),
            ("Date of Birth", 0.52),
            ("15/03/1990", 0.48),
            ("Nationality", 0.42),
            ("INDIAN", 0.38),
        ])

        let layout = LayoutIntelligenceAgent.analyze(document: doc, payloadHints: .empty)
        let result = await DocumentIntelligencePipeline.extract(document: doc)

        print("ROOT|passport_spatial|pairs=\(layout.labelValuePairs.map { "\($0.label)→\($0.value)" }.joined(separator: " | "))")
        print("ROOT|passport_spatial|suggestions=\(result.suggestions.map { "\($0.profileKey)=\($0.value)" }.joined(separator: " | "))")

        // Correct pairs for surname/given name should exist.
        XCTAssertTrue(layout.labelValuePairs.contains { $0.label == "Surname" && $0.value == "SHARMA" })
        XCTAssertTrue(result.suggestions.contains { $0.profileKey == ProfileFieldKey.legalLastName && $0.value == "SHARMA" })
        XCTAssertTrue(result.suggestions.contains { $0.profileKey == ProfileFieldKey.legalFirstName && $0.value == "PRIYA" })

        // Single-token values must not become labels that steal the next row.
        let badLabels = layout.labelValuePairs.filter { pair in
            ["SHARMA", "PRIYA", "INDIAN"].contains(pair.label.uppercased())
        }
        if !badLabels.isEmpty {
            print("ROOT|passport_spatial|BAD_LABELS=\(badLabels.map { "\($0.label)→\($0.value)" }.joined(separator: " | "))")
        }

        // Known failure from investigation: middle name polluted / wrong last name key.
        if let last = result.suggestions.first(where: { $0.profileKey == ProfileFieldKey.legalLastName }) {
            XCTAssertNotEqual(last.value, "Name", "legal_last_name must not be the literal token 'Name'")
        }
    }

    func testDriverLicenseNameValueMustNotLandInAddressField() async {
        // Texas-style DL: numbered fields; name row near address row — common mis-pair.
        let doc = VisionOcrAdapter.NormalizedDocument(pages: [
            VisionOcrAdapter.Page(blocks: [
                block("TEXAS DRIVER LICENSE", x: 0.1, y: 0.92),
                block("1. SMITH", x: 0.08, y: 0.82),
                block("2. JANE", x: 0.08, y: 0.76),
                block("8. Address", x: 0.08, y: 0.62),
                block("742 OAK STREET", x: 0.35, y: 0.62),
                block("AUSTIN", x: 0.35, y: 0.56),
                block("TX 78701", x: 0.55, y: 0.56),
                block("DOB: 03/15/1985", x: 0.08, y: 0.46),
                block("License No: D12345678", x: 0.08, y: 0.36),
            ]),
        ])

        let layout = LayoutIntelligenceAgent.analyze(document: doc, payloadHints: .empty)
        let direct = OpenVocabularyFieldExtractor.suggestions(
            from: layout,
            documentTypeHint: "drivers_license"
        )
        print("ROOT|dl_address|direct=\(direct.map { "\($0.profileKey)=\($0.value)" }.joined(separator: " | "))")
        let result = await DocumentIntelligencePipeline.extract(document: doc)

        print("ROOT|dl_address|pairs=\(layout.labelValuePairs.map { "\($0.label)→\($0.value)" }.joined(separator: " | "))")
        print("ROOT|dl_address|suggestions=\(result.suggestions.map { "\($0.profileKey)=\($0.value)" }.joined(separator: " | "))")

        if let address = result.suggestions.first(where: { $0.profileKey == ProfileFieldKey.addressLine1 }) {
            XCTAssertFalse(
                looksLikePersonName(address.value),
                "address_line1 must not hold a person name; got \(address.value)"
            )
            XCTAssertTrue(
                address.value.uppercased().contains("OAK") || address.value.uppercased().contains("742"),
                "address should be street text"
            )
        } else {
            XCTFail("expected address_line1 suggestion")
        }

        XCTAssertFalse(
            result.suggestions.contains { $0.profileKey == ProfileFieldKey.addressLine1 && looksLikePersonName($0.value) },
            "no person name may appear in address field"
        )
        XCTAssertTrue(
            result.suggestions.contains {
                $0.profileKey == ProfileFieldKey.legalLastName && $0.value.uppercased() == "SMITH"
            } || result.suggestions.contains {
                $0.profileKey == ProfileFieldKey.displayName && $0.value.uppercased().contains("SMITH")
            },
            "name row should map last/display name from SMITH"
        )
        XCTAssertTrue(
            result.suggestions.contains {
                $0.profileKey == ProfileFieldKey.legalFirstName && $0.value.uppercased() == "JANE"
            },
            "same-row supplement should map JANE as first name"
        )
    }

    func testUtilityBillGenericFormMapsExtensionAndCanonicalFields() async {
        let doc = VisionOcrAdapter.NormalizedDocument(pages: [
            VisionOcrAdapter.Page(blocks: [
                block("ACME ELECTRIC UTILITY", x: 0.1, y: 0.92),
                block("Account Number: 1234567890", x: 0.1, y: 0.82),
                block("Amount Due: $142.50", x: 0.1, y: 0.72),
                block("Due Date: 04/15/2026", x: 0.1, y: 0.62),
                block("Service Address: 742 Oak Street", x: 0.1, y: 0.52),
            ]),
        ])

        let result = await DocumentIntelligencePipeline.extract(document: doc)
        print("ROOT|utility|pairs trace suggestions=\(result.suggestions.map { "\($0.profileKey)=\($0.value)" }.joined(separator: " | "))")

        XCTAssertTrue(result.pipelineTrace.contains("extract:semantic"))
        XCTAssertTrue(result.suggestions.contains { $0.profileKey == "account_number" && $0.value == "1234567890" })
        XCTAssertTrue(result.suggestions.contains { $0.profileKey == ProfileFieldKey.addressLine1 && $0.value.contains("742") })
        XCTAssertFalse(
            result.suggestions.contains { $0.profileKey == ProfileFieldKey.addressLine1 && $0.value == "ACME" }
        )
    }

    func testNLAndBagLabelMappingsForCommonDriverLicenseLabels() {
        let probes: [(label: String, expected: String)] = [
            ("First Name", ProfileFieldKey.legalFirstName),
            ("Last Name", ProfileFieldKey.legalLastName),
            ("Name", ProfileFieldKey.displayName),
            ("8. Address", ProfileFieldKey.addressLine1),
            ("Address", ProfileFieldKey.addressLine1),
            ("DOB", ProfileFieldKey.dateOfBirth),
            ("Date of Expiry", ProfileFieldKey.driversLicenseExpiry),
            ("Date of Issue", ProfileFieldKey.driversLicenseIssueDate),
        ]

        for probe in probes {
            let bag = SemanticFieldLabelMapper.canonicalKey(for: probe.label)
            let nl = NLFieldLabelMapper.profileKey(
                forLabel: probe.label,
                documentType: .driversLicense,
                schemaKeys: ProfileSchema.allFields.map(\.key)
            )
            let resolved = SemanticFieldLabelMapper.resolve(
                label: probe.label,
                documentTypeHint: "drivers_license"
            )?.profileKey
            XCTAssertEqual(
                resolved ?? bag ?? nl,
                probe.expected,
                "Expected mapping for \(probe.label)"
            )
        }
    }

    func testDateFieldsMapToWrongDocumentWithoutTypeHint() async {
        let doc = VisionOcrAdapter.NormalizedDocument(pages: [
            VisionOcrAdapter.Page(blocks: [
                block("TEXAS DRIVER LICENSE", x: 0.1, y: 0.9),
                block("Date of Expiry: 03/15/2031", x: 0.1, y: 0.7),
            ]),
        ])
        let result = await DocumentIntelligencePipeline.extract(document: doc)
        print("ROOT|dl_expiry_no_hint|suggestions=\(result.suggestions.map { "\($0.profileKey)=\($0.value)" }.joined(separator: " | "))")

        if let expiry = result.suggestions.first(where: { $0.value == "03/15/2031" }) {
            // Without document type hint, ONNX maps "Date of Expiry" to passport_expiry (confirmed bug).
            print("ROOT|dl_expiry_no_hint|expiry_key=\(expiry.profileKey)")
        }
    }

    func testAddressCityStateZipMergedFromSeparateLines() async {
        let doc = VisionOcrAdapter.NormalizedDocument(pages: [
            VisionOcrAdapter.Page(blocks: [
                block("8. Address", x: 0.08, y: 0.62),
                block("742 OAK STREET", x: 0.35, y: 0.62),
                block("AUSTIN", x: 0.35, y: 0.56),
                block("TX 78701", x: 0.55, y: 0.56),
            ]),
        ])

        let result = await DocumentIntelligencePipeline.extract(document: doc)
        XCTAssertTrue(result.pipelineTrace.contains { $0.hasPrefix("address:merged:") || $0 == "validate:grounding" })
        XCTAssertTrue(result.suggestions.contains { $0.profileKey == ProfileFieldKey.addressLine1 && $0.value.contains("742") })
        XCTAssertTrue(result.suggestions.contains { $0.profileKey == ProfileFieldKey.city && $0.value.uppercased() == "AUSTIN" })
        XCTAssertTrue(result.suggestions.contains { $0.profileKey == ProfileFieldKey.state && $0.value == "TX" })
        XCTAssertTrue(result.suggestions.contains { $0.profileKey == ProfileFieldKey.postalCode && $0.value == "78701" })
    }

    func testUnstructuredDocumentUsesHeuristicFallback() async {
        let prose = """
        Dear Sir or Madam,
        My name is Jane Marie Smith and my identifier is 123-45-6789.
        I was born on 03/15/1985.
        Please contact me at 742 Oak Street, Austin, TX 78701.
        """
        let doc = VisionOcrAdapter.NormalizedDocument(pages: [
            VisionOcrAdapter.Page(blocks: prose.components(separatedBy: .newlines).enumerated().map { index, line in
                block(line, x: 0.08, y: Float(0.9 - Double(index) * 0.05))
            }),
        ])

        let result = await DocumentIntelligencePipeline.extract(document: doc, allowHeavyLLM: false)
        XCTAssertTrue(
            result.pipelineTrace.contains("route:unknown_semantic")
                || result.pipelineTrace.contains("route:known_fast")
        )
        XCTAssertTrue(result.usedHeuristicFallback || result.suggestions.contains { $0.profileKey == ProfileFieldKey.ssn })
        XCTAssertTrue(
            result.suggestions.contains { $0.profileKey == ProfileFieldKey.ssn }
                || result.suggestions.contains { $0.profileKey == ProfileFieldKey.displayName }
        )
    }

    // MARK: - Helpers

    private func verticalBlocks(_ lines: [(String, Float)]) -> VisionOcrAdapter.NormalizedDocument {
        VisionOcrAdapter.NormalizedDocument(pages: [
            VisionOcrAdapter.Page(blocks: lines.map { text, y in
                block(text, x: 0.1, y: y)
            }),
        ])
    }

    private func block(_ text: String, x: Float, y: Float) -> VisionOcrAdapter.TextBlock {
        VisionOcrAdapter.TextBlock(
            text: text,
            confidence: 0.95,
            bounds: VisionOcrAdapter.NormRect(x: x, y: y, width: 0.45, height: 0.04)
        )
    }

    private func looksLikePersonName(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.range(of: #"^[A-Za-z][A-Za-z\s\-'.]{0,40}$"#, options: .regularExpression) != nil else {
            return false
        }
        return trimmed.range(of: #"\d"#, options: .regularExpression) == nil
            && !trimmed.uppercased().contains("ST")
            && !trimmed.uppercased().contains("AVE")
            && !trimmed.uppercased().contains("RD")
    }
}
