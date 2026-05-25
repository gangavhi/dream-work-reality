import XCTest
@testable import DreamWorkApp

final class IntelligenceModuleTests: XCTestCase {
    func testSemanticFieldLabelMapperMapsSurname() {
        XCTAssertEqual(
            SemanticFieldLabelMapper.canonicalKey(for: "Surname"),
            ProfileFieldKey.legalLastName
        )
        XCTAssertEqual(
            SemanticFieldLabelMapper.canonicalKey(for: "Family Name"),
            ProfileFieldKey.legalLastName
        )
    }

    func testSemanticFieldLabelMapperMapsExtensionKeys() {
        let resolved = SemanticFieldLabelMapper.resolve(label: "Account Number")
        XCTAssertEqual(resolved?.profileKey, "account_number")
        XCTAssertTrue(resolved?.isExtension == true)

        let custom = SemanticFieldLabelMapper.resolve(label: "Lease Term Months")
        XCTAssertEqual(custom?.profileKey, "lease_term_months")
        XCTAssertTrue(custom?.isExtension == true)
    }

    func testOpenVocabularyExtractsUtilityBillFields() {
        let pairs = [
            OcrLayoutSerializer.LabelValuePair(label: "Account Number", value: "1234567890"),
            OcrLayoutSerializer.LabelValuePair(label: "Amount Due", value: "$142.50"),
            OcrLayoutSerializer.LabelValuePair(label: "Due Date", value: "04/15/2026"),
            OcrLayoutSerializer.LabelValuePair(label: "Service Address", value: "742 Oak Street"),
        ]
        let layout = LayoutIntelligenceAgent.LayoutDocument(
            layoutText: pairs.map { "\($0.label) | \($0.value)" }.joined(separator: "\n"),
            modelInput: "",
            blocks: [],
            labelValuePairs: pairs,
            engineID: "test"
        )
        let suggestions = OpenVocabularyFieldExtractor.suggestions(
            from: layout,
            documentTypeHint: "utility_bill"
        )
        XCTAssertTrue(suggestions.contains { $0.profileKey == "account_number" && $0.value == "1234567890" })
        XCTAssertTrue(suggestions.contains { $0.profileKey == "amount_due" && $0.value == "$142.50" })
        XCTAssertTrue(suggestions.contains { $0.profileKey == "due_date" && $0.value == "04/15/2026" })
        XCTAssertTrue(suggestions.contains { $0.profileKey == ProfileFieldKey.addressLine1 })
    }

    func testTemplateMatchExtractsMVPDriverLicenseFields() {
        let pairs = [
            OcrLayoutSerializer.LabelValuePair(label: "First Name", value: "Jane"),
            OcrLayoutSerializer.LabelValuePair(label: "Last Name", value: "Smith"),
            OcrLayoutSerializer.LabelValuePair(label: "DOB", value: "03/15/1985"),
            OcrLayoutSerializer.LabelValuePair(label: "License No", value: "D12345678"),
        ]
        let layout = LayoutIntelligenceAgent.LayoutDocument(
            layoutText: "TEXAS DRIVER LICENSE\nCLASS C\n" + pairs.map { "\($0.label): \($0.value)" }.joined(separator: "\n"),
            modelInput: "",
            blocks: [],
            labelValuePairs: pairs,
            engineID: "test"
        )
        let classification = Self.testClassification(openType: "drivers_license")

        let match = DocumentTemplateAgent.match(layout: layout, classification: classification)
        XCTAssertEqual(match?.templateID, "template.drivers_license.v1")

        let suggestions = match.map { DocumentTemplateAgent.extract(layout: layout, match: $0) } ?? []
        XCTAssertTrue(suggestions.contains { $0.profileKey == ProfileFieldKey.legalFirstName && $0.mappingSource == .template })
        XCTAssertTrue(suggestions.contains { $0.profileKey == ProfileFieldKey.driversLicenseNumber && $0.mappingSource == .template })
    }

    func testTemplateCoordinateExtractionUsesBoundingBoxesAndValidation() {
        let blocks = [
            OcrLayoutSerializer.LayoutBlock(text: "TEXAS DRIVER LICENSE", confidence: 0.96, x: 0.1, y: 0.9, width: 0.6, height: 0.05),
            OcrLayoutSerializer.LayoutBlock(text: "First Name: Jane", confidence: 0.95, x: 0.1, y: 0.8, width: 0.4, height: 0.05),
            OcrLayoutSerializer.LayoutBlock(text: "Last Name: Smith", confidence: 0.95, x: 0.1, y: 0.68, width: 0.4, height: 0.05),
            OcrLayoutSerializer.LayoutBlock(text: "DOB: 03/15/1985", confidence: 0.95, x: 0.1, y: 0.56, width: 0.4, height: 0.05),
            OcrLayoutSerializer.LayoutBlock(text: "License No: D12345678", confidence: 0.95, x: 0.1, y: 0.44, width: 0.5, height: 0.05),
        ]
        let layout = LayoutIntelligenceAgent.LayoutDocument(
            layoutText: blocks.map(\.text).joined(separator: "\n"),
            modelInput: "",
            blocks: blocks,
            labelValuePairs: [],
            engineID: "test"
        )
        let classification = Self.testClassification(openType: "drivers_license")
        let match = DocumentTemplateAgent.match(layout: layout, classification: classification)
        let suggestions = match.map { DocumentTemplateAgent.extract(layout: layout, match: $0) } ?? []

        XCTAssertEqual(suggestions.first { $0.profileKey == ProfileFieldKey.legalFirstName }?.value, "Jane")
        XCTAssertEqual(suggestions.first { $0.profileKey == ProfileFieldKey.driversLicenseNumber }?.value, "D12345678")
        XCTAssertTrue(suggestions.allSatisfy { $0.mappingSource == .template })
    }

    func testExtractionStrategyBranchesByDocumentStructure() {
        let classifiedLayout = LayoutIntelligenceAgent.LayoutDocument(
            layoutText: "INSURANCE CARD\nMember ID | ABC123\nCarrier | Acme Health",
            modelInput: "",
            blocks: [],
            labelValuePairs: [
                OcrLayoutSerializer.LabelValuePair(label: "Member ID", value: "ABC123"),
                OcrLayoutSerializer.LabelValuePair(label: "Carrier", value: "Acme Health"),
            ],
            engineID: "test"
        )
        let classification = Self.testClassification(openType: "insurance_card")
        let template = DocumentTemplateAgent.match(layout: classifiedLayout, classification: classification)
        XCTAssertEqual(
            ExtractionStrategyAgent.determine(
                layout: classifiedLayout,
                classification: classification,
                templateMatch: template
            ).structure,
            .structured
        )

        let unknownLayout = LayoutIntelligenceAgent.LayoutDocument(
            layoutText: "This page has paragraphs without clear labels.",
            modelInput: "This page has paragraphs without clear labels.",
            blocks: [],
            labelValuePairs: [],
            engineID: "test"
        )
        let unknown = ClassificationAgent.classify(modelInput: unknownLayout.layoutText, mappedDocumentType: nil, machineReadableSources: [])
        XCTAssertEqual(
            ExtractionStrategyAgent.determine(layout: unknownLayout, classification: unknown, templateMatch: nil).structure,
            .layoutAI
        )
    }

    func testDocumentTypeSchemaKeysAreOpenVocabulary() {
        XCTAssertEqual(ProfileSchemaKeysForDocument.inferOpenType(from: "VISA\nVisa Number V1234567"), "visa")

        XCTAssertTrue(ProfileSchemaKeysForDocument.keys(forOpenDocumentType: "utility_bill").isEmpty)
        XCTAssertTrue(ProfileSchemaKeysForDocument.keys(forOpenDocumentType: "bank_statement").isEmpty)
        XCTAssertTrue(ProfileSchemaKeysForDocument.keys(forOpenDocumentType: "visa").isEmpty)
    }

    func testLocalEmbeddingMatcherHandlesSemanticLabels() {
        XCTAssertEqual(
            SemanticFieldLabelMapper.resolve(label: "Applicant Legal Family")?.profileKey,
            ProfileFieldKey.legalLastName
        )
        XCTAssertEqual(
            SemanticFieldLabelMapper.resolve(label: "Applicant Mailing Street")?.profileKey,
            ProfileFieldKey.addressLine1
        )
    }

    func testLayoutAwareExtractorChunksLongInput() {
        let text = (0..<120).map { "Line \($0) Account Number 12345" }.joined(separator: "\n")
        let chunks = LayoutAwareSemanticExtractor.makeChunks(from: text, documentType: "unknown", maxCharacters: 400)
        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertTrue(chunks.allSatisfy { !$0.text.isEmpty })
    }

    func testLearningAppliesOnlyGroundedCorrections() {
        #if DEBUG
        IncrementalLearningStore.clearForTests()
        defer { IncrementalLearningStore.clearForTests() }
        #endif

        IncrementalLearningStore.record(
            profileKey: ProfileFieldKey.insuranceMemberId,
            originalValue: "OCR-123",
            correctedValue: "MEM-9999",
            documentType: "insurance_card"
        )

        let suggestions = IncrementalLearningStore.learnedSuggestions(
            documentType: "insurance_card",
            ocrText: "Insurance Card\nMember ID MEM-9999",
            existingKeys: []
        )
        XCTAssertTrue(suggestions.contains { $0.profileKey == ProfileFieldKey.insuranceMemberId && $0.mappingSource == .learned })

        let ungrounded = IncrementalLearningStore.learnedSuggestions(
            documentType: "insurance_card",
            ocrText: "Insurance Card\nMember ID DIFFERENT",
            existingKeys: []
        )
        XCTAssertTrue(ungrounded.isEmpty)
    }

    func testCanonicalIdentitySchemaAndAutofillPayload() {
        let suggestions = [
            OcrFieldSuggestion(profileKey: ProfileFieldKey.legalFirstName, label: "First", value: "Jane", confidence: "High"),
            OcrFieldSuggestion(profileKey: ProfileFieldKey.legalLastName, label: "Last", value: "Smith", confidence: "High"),
            OcrFieldSuggestion(profileKey: ProfileFieldKey.dateOfBirth, label: "DOB", value: "03/15/1985", confidence: "High"),
            OcrFieldSuggestion(profileKey: ProfileFieldKey.ssn, label: "SSN", value: "123-45-6789", confidence: "High"),
        ]

        let graph = DocumentKnowledgeGraph.buildIdentityGraph(from: suggestions, documentType: "tax_w2")
        XCTAssertEqual(graph.autofillPayload.canonicalIdentity.person.firstName, "Jane")
        XCTAssertEqual(graph.autofillPayload.canonicalIdentity.person.lastName, "Smith")
        XCTAssertEqual(graph.autofillPayload.canonicalIdentity.identity.ssnLast4, "6789")

        let response = SmartAutofillSDK.buildResponse(
            from: graph.autofillPayload,
            request: SmartAutofillSDK.Request(requestedKeys: [ProfileFieldKey.legalFirstName])
        )
        XCTAssertEqual(response.fields[ProfileFieldKey.legalFirstName], "Jane")
        XCTAssertNil(response.fields[ProfileFieldKey.legalLastName])
    }

    func testKnowledgeGraphMapsAddressFields() {
        let entities = DocumentKnowledgeGraph.entities(
            from: [
                OcrFieldSuggestion(
                    profileKey: ProfileFieldKey.city,
                    label: "City",
                    value: "Austin",
                    confidence: "High"
                ),
            ],
            documentType: "utility_bill"
        )
        XCTAssertEqual(entities.first?.type, .address)
    }

    func testVectorDocumentMemorySearch() {
        VectorDocumentMemory.index(documentType: "tax_w2", plainText: "W-2 wages employer 2024")
        let hits = VectorDocumentMemory.search(query: "w-2 employer")
        XCTAssertFalse(hits.isEmpty)
    }

    private static func testClassification(openType: String) -> ClassificationAgent.Result {
        let presentation = DocumentTypePresentation.resolve(openType)
        return ClassificationAgent.Result(
            openDocumentType: openType,
            displayLabel: presentation.displayLabel,
            enumType: presentation.enumType,
            confidence: 1.0,
            engineID: "test.local_ml",
            issuerRegion: nil,
            country: nil,
            runtimeStatus: "classifier_active"
        )
    }
}
