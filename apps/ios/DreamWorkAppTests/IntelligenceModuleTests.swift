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

    func testConfidenceOrchestratorFlagsLowConfidenceEstimated() {
        let suggestion = OcrFieldSuggestion(
            profileKey: ProfileFieldKey.displayName,
            label: "Name",
            value: "Not In OCR",
            confidence: "Estimated",
            confidenceScore: 0.52,
            mappingSource: .estimated
        )
        let breakdown = ConfidenceOrchestrator.score(
            suggestion: suggestion,
            documentType: .other,
            ocrCorpus: "utility bill account",
            averageOCRBlockConfidence: 0.9
        )
        XCTAssertTrue(breakdown.requiresManualConfirmation)
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
}
