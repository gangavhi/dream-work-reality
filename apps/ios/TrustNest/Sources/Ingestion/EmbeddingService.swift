import Foundation
import CoreML
import NaturalLanguage

/// Produces 768-dimensional embeddings for sqlite-vec `float[768]` columns.
enum EmbeddingService {
    static let dimension = 768

    static func embed(_ text: String) throws -> [Float] {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else {
            return Array(repeating: 0, count: dimension)
        }

        if let modelVector = try? CoreMLEmbeddingVector.from(text: normalized) {
            return modelVector
        }

        // Apple-native fallback: NLEmbedding sentence vectors expanded to spec dimension.
        return NaturalLanguageEmbedding.fallbackVector(for: normalized, dimension: dimension)
    }

    static func vectorLiteral(_ vector: [Float]) -> String {
        let values = vector.map { String($0) }.joined(separator: ", ")
        return "[\(values)]"
    }
}

private enum CoreMLEmbeddingVector {
    static func from(text: String) throws -> [Float] {
        guard let modelURL = Bundle.main.url(forResource: "TextEmbedding768", withExtension: "mlmodelc") else {
            throw EmbeddingError.modelUnavailable
        }
        let model = try MLModel(contentsOf: modelURL)
        let input = try MLDictionaryFeatureProvider(dictionary: ["text": text])
        let output = try model.prediction(from: input)
        guard let multiArray = output.featureValue(for: "embedding")?.multiArrayValue else {
            throw EmbeddingError.invalidOutput
        }
        var result = [Float](repeating: 0, count: EmbeddingService.dimension)
        for index in 0..<min(result.count, multiArray.count) {
            result[index] = multiArray[index].floatValue
        }
        return result
    }
}

private enum NaturalLanguageEmbedding {
    static func fallbackVector(for text: String, dimension: Int) -> [Float] {
        var vector = [Float](repeating: 0, count: dimension)

        if let sentence = NLEmbedding.sentenceEmbedding(for: .english) {
            let partial = sentence.vector(for: text) ?? []
            for (index, value) in partial.enumerated() where index < dimension {
                vector[index] = Float(value)
            }
        }

        // Spread token signal across remaining dimensions for stable cosine ranking.
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var tokenIndex = 0
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let token = String(text[range])
            let hash = abs(token.hashValue)
            let slot = hash % dimension
            vector[slot] += 0.05
            tokenIndex += 1
            return true
        }

        let magnitude = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        guard magnitude > 0 else { return vector }
        return vector.map { $0 / magnitude }
    }
}

private enum EmbeddingError: Error {
    case modelUnavailable
    case invalidOutput
}
