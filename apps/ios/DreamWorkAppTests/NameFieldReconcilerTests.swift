import XCTest
@testable import DreamWorkApp

final class NameFieldReconcilerTests: XCTestCase {
    func testReconcilesSwappedFirstAndLastFromDisplayName() {
        let suggestions = [
            OcrFieldSuggestion(
                profileKey: ProfileFieldKey.displayName,
                label: "Full name",
                value: "Jane Smith",
                confidence: "High",
                confidenceScore: 0.9
            ),
            OcrFieldSuggestion(
                profileKey: ProfileFieldKey.legalFirstName,
                label: "Legal first name",
                value: "Smith",
                confidence: "High",
                confidenceScore: 0.95
            ),
            OcrFieldSuggestion(
                profileKey: ProfileFieldKey.legalLastName,
                label: "Legal last name",
                value: "Jane",
                confidence: "High",
                confidenceScore: 0.95
            ),
        ]

        let reconciled = NameFieldReconciler.reconcile(suggestions)
        let byKey = Dictionary(uniqueKeysWithValues: reconciled.map { ($0.profileKey, $0.value) })

        XCTAssertEqual(byKey[ProfileFieldKey.displayName], "Jane Smith")
        XCTAssertEqual(byKey[ProfileFieldKey.legalFirstName], "Jane")
        XCTAssertEqual(byKey[ProfileFieldKey.legalLastName], "Smith")
    }

    func testSplitDisplayNameHandlesMiddleName() {
        let split = NameFieldReconciler.splitDisplayName("Jane Marie Smith")
        XCTAssertEqual(split.first, "Jane")
        XCTAssertEqual(split.middle, "Marie")
        XCTAssertEqual(split.last, "Smith")
    }

    func testSplitDisplayNameHandlesLastCommaFirst() {
        let split = NameFieldReconciler.splitDisplayName("Smith, Jane")
        XCTAssertEqual(split.first, "Jane")
        XCTAssertEqual(split.last, "Smith")
    }
}
