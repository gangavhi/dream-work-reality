import XCTest
@testable import DreamWorkApp

final class GenAIFieldMapperTests: XCTestCase {
    func testParseStructuredExtractionWithDocumentLabels() {
        let json = """
        {
          "issuer_region": "TX",
          "country": "US",
          "fields": {
            "drivers_license_number": {"value": "D12345678", "label": "Driver License No"},
            "legal_first_name": {"value": "Jane", "label": "First name"},
            "legal_last_name": {"value": "Smith", "label": "Last name"},
            "date_of_birth": {"value": "03/15/1985", "label": "DOB"}
          }
        }
        """
        let suggestions = GenAIFieldMapper.suggestions(
            from: parseTestExtraction(json),
            documentType: .driversLicense
        )
        let byKey = Dictionary(uniqueKeysWithValues: suggestions.map { ($0.profileKey, $0.label) })
        XCTAssertEqual(byKey[ProfileFieldKey.driversLicenseNumber], "Driver License No")
        XCTAssertEqual(byKey[ProfileFieldKey.legalFirstName], "First name")
        XCTAssertEqual(byKey[ProfileFieldKey.legalLastName], "Last name")
        XCTAssertEqual(byKey[ProfileFieldKey.dateOfBirth], "DOB")
    }

    func testGenAILabelsStoredOnDriverLicenseResult() {
        let extraction = GenAIFieldMapper.ExtractionResult(
            values: [
                ProfileFieldKey.driversLicenseNumber: "D12345678",
                ProfileFieldKey.driversLicenseState: "TX",
            ],
            labels: [ProfileFieldKey.driversLicenseNumber: "Driver License No"],
            documentType: "drivers_license",
            issuerRegion: "TX",
            country: "US"
        )
        let result = GenAIFieldMapper.driverLicenseResult(from: extraction, rawText: "test")
        let suggestions = DriverLicenseFieldMapper.suggestions(from: result)
        let dl = suggestions.first { $0.profileKey == ProfileFieldKey.driversLicenseNumber }
        XCTAssertEqual(dl?.label, "Driver License No")
    }

    private func parseTestExtraction(_ json: String) -> GenAIFieldMapper.ExtractionResult {
        // Mirror internal parser via suggestions(from values) path — use driverLicenseResult round-trip
        let data = json.data(using: .utf8)!
        let obj = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        var values: [String: String] = [:]
        var labels: [String: String] = [:]
        if let fields = obj["fields"] as? [String: Any] {
            for (key, entry) in fields {
                let canon = key
                if let dict = entry as? [String: Any] {
                    values[canon] = dict["value"] as? String
                    labels[canon] = dict["label"] as? String
                }
            }
        }
        return GenAIFieldMapper.ExtractionResult(
            values: values,
            labels: labels,
            documentType: obj["document_type"] as? String,
            issuerRegion: obj["issuer_region"] as? String,
            country: obj["country"] as? String
        )
    }
}
