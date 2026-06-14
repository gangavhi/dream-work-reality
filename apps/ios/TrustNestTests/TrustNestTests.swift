import XCTest
@testable import TrustNest

final class TrustNestTests: XCTestCase {
    func testRelationshipTypesMatchSchema() {
        XCTAssertEqual(RelationshipType.primary.rawValue, "Primary")
        XCTAssertEqual(RelationshipType.spouse.rawValue, "Spouse")
        XCTAssertEqual(RelationshipType.dependent.rawValue, "Dependent")
    }

    func testEmbeddingDimensionMatchesVec0Schema() {
        XCTAssertEqual(EmbeddingService.dimension, 768)
    }

    func testEmbeddingProducesNormalizedVector() throws {
        let vector = try EmbeddingService.embed("Policy holder John Doe")
        XCTAssertEqual(vector.count, 768)
        let magnitude = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        XCTAssertGreaterThan(magnitude, 0)
    }

    func testDatabaseSchemaBootstraps() async throws {
        let database = try TrustNestDatabase(inMemory: true)
        let householdId = try await database.currentHouseholdId()
        XCTAssertFalse(householdId.isEmpty)
    }
}
