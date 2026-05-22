import XCTest
@testable import DreamWorkApp

final class OnDeviceFieldMapperTests: XCTestCase {
    func testMapsLabelValuePairsViaRustFFI() {
        let layout = """
        ## Spatial label | value pairs (heuristic)
        DOB | 03/15/1985
        License No | D12345678
        First name | Jane
        Last name | Smith
        """
        let previous = GenAISettings.provider
        GenAISettings.provider = .onDevice
        defer { GenAISettings.provider = previous }

        let result = OnDeviceFieldMapper.mapFields(
            layoutText: layout,
            profileSchemaKeys: ProfileSchema.allFields.map(\.key)
        )
        XCTAssertNotNil(result)
        let keys = Set(result!.suggestions.map(\.profileKey))
        XCTAssertTrue(keys.contains(ProfileFieldKey.dateOfBirth))
        XCTAssertTrue(keys.contains(ProfileFieldKey.driversLicenseNumber))
        XCTAssertTrue(keys.contains(ProfileFieldKey.legalFirstName))
    }
}
