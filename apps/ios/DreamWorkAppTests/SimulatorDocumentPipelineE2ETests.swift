import XCTest

@testable import DreamWorkApp

/// Simulator E2E: real document images → Vision OCR → full intelligence pipeline.
@MainActor
final class SimulatorDocumentPipelineE2ETests: XCTestCase {
    private struct FixtureCase {
        let resource: String
        let ext: String
        let label: String
    }

    private let fixtures: [FixtureCase] = [
        FixtureCase(resource: "texas-driver-license-sample", ext: "png", label: "Texas driver license photo"),
        FixtureCase(resource: "sample-document", ext: "png", label: "US passport sample"),
    ]

    func testFixtureImagesRunVisionOCRAndPipeline() async throws {
        let bundle = Bundle(for: type(of: self))
        let previous = GenAISettings.provider
        GenAISettings.provider = .appleNative
        defer { GenAISettings.provider = previous }

        var ran = 0
        for fixture in fixtures {
            guard let url = bundle.url(forResource: fixture.resource, withExtension: fixture.ext) else {
                print("SKIP missing fixture: \(fixture.resource).\(fixture.ext)")
                continue
            }
            ran += 1
            try await runPipelineE2E(url: url, label: fixture.label)
        }
        XCTAssertGreaterThan(ran, 0, "Add fixtures under DreamWorkAppTests/Fixtures/ to run simulator OCR E2E")
    }

    func testTexasDriverLicenseReferenceFieldMapping() async throws {
        let bundle = Bundle(for: type(of: self))
        let diskPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/texas-driver-license-reference.png")
        let url = bundle.url(forResource: "texas-driver-license-reference", withExtension: "png")
            ?? (FileManager.default.fileExists(atPath: diskPath.path) ? diskPath : nil)
        guard let url else {
            throw XCTSkip("Missing DreamWorkAppTests/Fixtures/texas-driver-license-reference.png")
        }

        let result = try await runPipelineE2E(url: url, label: "Texas driver license reference photo")
        let byKey = Dictionary(uniqueKeysWithValues: result.suggestions.map { ($0.profileKey, $0.value) })

        XCTAssertEqual(result.displayType, .driversLicense)
        XCTAssertEqual(byKey[ProfileFieldKey.driversLicenseState], "TX")
        XCTAssertEqual(byKey[ProfileFieldKey.state], "TX")

        let last = byKey[ProfileFieldKey.legalLastName] ?? ""
        let first = byKey[ProfileFieldKey.legalFirstName] ?? ""
        XCTAssertGreaterThanOrEqual(last.count, 3, "Expected a plausible last name, got \(last)")
        XCTAssertGreaterThanOrEqual(first.count, 5, "Expected a plausible first name, got \(first)")
        XCTAssertNotEqual(last.lowercased(), "director")
        XCTAssertFalse(first.lowercased().contains("director"))

        if let dob = byKey[ProfileFieldKey.dateOfBirth] {
            XCTAssertTrue(dob.hasPrefix("06/"), "DOB month should be June from card, got \(dob)")
            XCTAssertTrue(dob.hasSuffix("/1990"), "DOB year should be 1990, got \(dob)")
        } else {
            XCTFail("Missing date of birth")
        }

        if let dl = byKey[ProfileFieldKey.driversLicenseNumber] {
            XCTAssertGreaterThanOrEqual(dl.filter(\.isNumber).count, 7, "DL number should have ≥7 digits, got \(dl)")
            XCTAssertFalse(dl.contains("-"), "DL number must not be ZIP+4, got \(dl)")
        } else {
            XCTFail("Missing driver license number")
        }

        if let zip = byKey[ProfileFieldKey.postalCode] {
            XCTAssertEqual(zip.count, 5, "ZIP should be 5 digits, got \(zip)")
        }

        XCTAssertNotNil(byKey[ProfileFieldKey.driversLicenseExpiry], "Expected expiry date")
        XCTAssertGreaterThan(result.suggestions.count, 5, "Photo scan should yield multiple DL fields")
    }

    func testTexasDriverLicenseSampleFieldMapping() async throws {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: "texas-driver-license-sample", withExtension: "png") else {
            throw XCTSkip("Missing DreamWorkAppTests/Fixtures/texas-driver-license-sample.png")
        }

        let previous = GenAISettings.provider
        GenAISettings.provider = .appleNative
        defer { GenAISettings.provider = previous }

        let result = try await runPipelineE2E(url: url, label: "Texas driver license photo")
        let byKey = Dictionary(uniqueKeysWithValues: result.suggestions.map { ($0.profileKey, $0.value) })

        XCTAssertEqual(result.displayType, .driversLicense)
        XCTAssertEqual(byKey[ProfileFieldKey.legalLastName], "Hiremath")
        XCTAssertEqual(byKey[ProfileFieldKey.driversLicenseState], "TX")

        let first = byKey[ProfileFieldKey.legalFirstName] ?? ""
        XCTAssertTrue(
            first.localizedCaseInsensitiveContains("gangadhar") || first.localizedCaseInsensitiveContains("cambadhar"),
            "Given name should come from a long name line, not a surname echo (got \(first))"
        )
        XCTAssertFalse(first.localizedCaseInsensitiveContains("hirehath"))

        let display = byKey[ProfileFieldKey.displayName] ?? ""
        XCTAssertTrue(display.localizedCaseInsensitiveContains("hiremath"))
        XCTAssertFalse(display.localizedCaseInsensitiveContains("court"))
        XCTAssertFalse(display.localizedCaseInsensitiveContains("marly"))

        XCTAssertEqual(byKey[ProfileFieldKey.dateOfBirth], "1983-06-01")
        XCTAssertEqual(byKey[ProfileFieldKey.driversLicenseIssueDate], "2025-04-22")
        XCTAssertEqual(byKey[ProfileFieldKey.driversLicenseExpiry], "2028-03-17")

        if let dl = byKey[ProfileFieldKey.driversLicenseNumber] {
            XCTAssertTrue(dl.contains("427"), "DL number should be partially recognized (got \(dl))")
        }
        if let street = byKey[ProfileFieldKey.addressLine1] {
            XCTAssertTrue(street.localizedCaseInsensitiveContains("court"))
        }
        if let city = byKey[ProfileFieldKey.city] {
            XCTAssertTrue(city.lowercased().hasPrefix("celi"))
        }
    }

    @discardableResult
    private func runPipelineE2E(url: URL, label: String) async throws -> DocumentIntelligencePipeline.Result {
        let bridge = RustCoreBridgeService()
        let summary = try await DocumentTextExtractor.extractAndPersist(from: url) { json in
            bridge.ingestNormalizedDocumentJSON(json)
        }
        XCTAssertGreaterThan(summary.blockCount, 0, "Vision OCR must detect text for \(label)")

        guard let json = bridge.peekLastNormalizedDocumentJSON(),
              let data = json.data(using: .utf8),
              let document = try? JSONDecoder().decode(VisionOcrAdapter.NormalizedDocument.self, from: data)
        else {
            XCTFail("Could not load normalized document JSON for \(label)")
            throw NSError(domain: "SimulatorDocumentPipelineE2ETests", code: 1)
        }

        let result = await DocumentIntelligencePipeline.extract(document: document, fileURL: url)

        print("=== Simulator E2E: \(label) ===")
        print("blocks=\(summary.blockCount) suggestions=\(result.suggestions.count)")
        print(result.pipelineTrace.joined(separator: " → "))
        print("displayType=\(result.displayType.rawValue) openLabel=\(result.openDocumentTypeLabel)")
        let rawLines = OcrFieldSuggester.fullText(from: document)
        print("--- OCR reading order ---")
        print(rawLines)
        print("--- mapped fields ---")
        for s in result.suggestions {
            print("  \(s.profileKey)=\(s.value) conf=\(s.confidence)")
        }

        XCTAssertGreaterThan(result.suggestions.count, 0, "\(label) should yield profile field suggestions")
        return result
    }
}
