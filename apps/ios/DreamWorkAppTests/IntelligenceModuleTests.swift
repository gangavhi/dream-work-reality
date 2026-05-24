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
