import XCTest
@testable import DreamWorkApp

final class OcrGroundingValidatorTests: XCTestCase {
    func testDropsUngroundedHeuristicValue() {
        let suggestion = OcrFieldSuggestion(
            profileKey: ProfileFieldKey.displayName,
            label: "Full name",
            value: "Totally Invented Name",
            confidence: "Estimated",
            confidenceScore: 0.52,
            mappingSource: .estimated
        )
        let filtered = OcrGroundingValidator.filter(
            [suggestion],
            ocrCorpus: "Utility bill for 123 Main St",
            trustedProfileKeys: []
        )
        XCTAssertTrue(filtered.isEmpty)
    }

    func testKeepsGroundedValue() {
        let suggestion = OcrFieldSuggestion(
            profileKey: ProfileFieldKey.city,
            label: "City",
            value: "Austin",
            confidence: "Estimated",
            confidenceScore: 0.5,
            mappingSource: .estimated
        )
        let filtered = OcrGroundingValidator.filter(
            [suggestion],
            ocrCorpus: "Service address\nAustin, TX 78701",
            trustedProfileKeys: []
        )
        XCTAssertEqual(filtered.count, 1)
    }

    func testKeepsBarcodeTaggedWithoutSubstring() {
        let suggestion = OcrFieldSuggestion(
            profileKey: ProfileFieldKey.driversLicenseNumber,
            label: "DL number",
            value: "X1234567",
            confidence: "High",
            confidenceScore: 0.94,
            mappingSource: .barcode
        )
        let filtered = OcrGroundingValidator.filter(
            [suggestion],
            ocrCorpus: "blurry scan",
            trustedProfileKeys: []
        )
        XCTAssertEqual(filtered.count, 1)
    }
}
