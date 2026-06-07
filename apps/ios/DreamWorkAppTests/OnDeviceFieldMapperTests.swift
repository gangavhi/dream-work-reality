import XCTest
@testable import DreamWorkApp

final class OnDeviceFieldMapperTests: XCTestCase {
    func testMissingGGUFReturnsFailVisibleEmptySuggestions() {
        let layout = """
        DOB | 03/15/1985
        License No | D12345678
        First name | Jane
        Last name | Smith
        """
        let previous = GenAISettings.provider
        GenAISettings.provider = .appleNative
        defer { GenAISettings.provider = previous }

        let result = OnDeviceFieldMapper.mapFields(
            layoutText: layout,
            profileSchemaKeys: ProfileSchema.allFields.map(\.key)
        )
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.suggestions.isEmpty)
        XCTAssertEqual(result!.llmRuntimeStatus, "llm_document_parser_failed:model_missing")
    }
}
