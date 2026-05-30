import XCTest
@testable import DreamWorkApp

final class OnnxFieldLabelMapperTests: XCTestCase {
    func testMiniLMMapsDriverLicenseLabelsWhenModelInstalled() throws {
        guard MiniLMOnnxFieldEmbedder.shared.isAvailable else {
            throw XCTSkip("MiniLM ONNX not installed — run apps/ios/scripts/download-minilm-onnx-model.sh")
        }

        XCTAssertEqual(
            OnnxFieldLabelMapper.canonicalKey(for: "Applicant Legal Family"),
            ProfileFieldKey.legalLastName
        )
        XCTAssertEqual(
            OnnxFieldLabelMapper.canonicalKey(for: "DL Number"),
            ProfileFieldKey.driversLicenseNumber
        )
        XCTAssertEqual(
            OnnxFieldLabelMapper.canonicalKey(for: "Birth Date"),
            ProfileFieldKey.dateOfBirth
        )
    }

    func testEmbedderProducesNormalizedVector() throws {
        guard MiniLMOnnxFieldEmbedder.shared.isAvailable else {
            throw XCTSkip("MiniLM ONNX not installed")
        }
        guard let vector = MiniLMOnnxFieldEmbedder.shared.embed("first name") else {
            XCTFail("expected embedding vector")
            return
        }
        XCTAssertEqual(vector.count, MiniLMOnnxFieldEmbedder.hiddenSize)
        let norm = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        XCTAssertEqual(norm, 1, accuracy: 0.001)
    }
}
