import CoreML
import Foundation

/// Runs model-based layout pairing. Heuristic label/value pairing is intentionally not used.
enum LayoutLMv3CoreMLAdapter {
    struct Result: Hashable {
        let pairs: [OcrLayoutSerializer.LabelValuePair]
        let status: String
    }

    private struct PairDTO: Decodable {
        let label: String
        let value: String
    }

    private struct PairsEnvelope: Decodable {
        let pairs: [PairDTO]
    }

    static func inferPairs(
        blocks: [OcrLayoutSerializer.LayoutBlock],
        modelPath: String
    ) -> Result {
        guard !blocks.isEmpty else {
            return Result(pairs: [], status: "\(ModelArtifactSlot.layoutLM.rawValue):empty_ocr")
        }

        do {
            let model = try MLModel(contentsOf: URL(fileURLWithPath: modelPath))
            let provider = try makeInputProvider(model: model, blocks: blocks)
            let prediction = try model.prediction(from: provider)
            let pairs = try decodePairs(from: prediction, blocks: blocks)
            let status = pairs.isEmpty
                ? "\(ModelArtifactSlot.layoutLM.rawValue):no_pairs"
                : "\(ModelArtifactSlot.layoutLM.rawValue):active"
            return Result(pairs: pairs, status: status)
        } catch {
            return Result(
                pairs: [],
                status: "\(ModelArtifactSlot.layoutLM.rawValue):failed:\(statusReason(error))"
            )
        }
    }

    private static func makeInputProvider(
        model: MLModel,
        blocks: [OcrLayoutSerializer.LayoutBlock]
    ) throws -> MLFeatureProvider {
        let descriptions = model.modelDescription.inputDescriptionsByName
        var features: [String: MLFeatureValue] = [:]

        for (name, description) in descriptions {
            if description.type == .string {
                features[name] = MLFeatureValue(string: ocrJSON(from: blocks))
                continue
            }

            guard description.type == .multiArray else {
                if description.isOptional { continue }
                throw AdapterError.unsupportedInput(name)
            }

            let lower = name.lowercased()
            if lower.contains("input") && lower.contains("id") {
                features[name] = try MLFeatureValue(multiArray: tokenIDs(for: blocks, description: description))
            } else if lower.contains("attention") || lower.contains("mask") {
                features[name] = try MLFeatureValue(multiArray: attentionMask(for: blocks, description: description))
            } else if lower.contains("bbox") || lower.contains("box") {
                features[name] = try MLFeatureValue(multiArray: boundingBoxes(for: blocks, description: description))
            } else if lower.contains("token_type") || lower.contains("segment") {
                features[name] = try MLFeatureValue(multiArray: zeros(description: description))
            } else if lower.contains("pixel") || lower.contains("image") {
                features[name] = try MLFeatureValue(multiArray: zeros(description: description))
            } else if description.isOptional {
                continue
            } else {
                throw AdapterError.unsupportedInput(name)
            }
        }

        return try MLDictionaryFeatureProvider(dictionary: features)
    }

    private static func decodePairs(
        from prediction: MLFeatureProvider,
        blocks: [OcrLayoutSerializer.LayoutBlock]
    ) throws -> [OcrLayoutSerializer.LabelValuePair] {
        if let json = stringOutput(from: prediction) {
            return pairs(fromJSON: json)
        }

        if let logits = multiArrayOutput(from: prediction) {
            return pairs(fromRoleLogits: logits, blocks: blocks)
        }

        throw AdapterError.unsupportedOutput
    }

    private static func stringOutput(from prediction: MLFeatureProvider) -> String? {
        for name in prediction.featureNames {
            guard let value = prediction.featureValue(for: name), value.type == .string else { continue }
            let text = value.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return text }
        }
        return nil
    }

    private static func pairs(fromJSON json: String) -> [OcrLayoutSerializer.LabelValuePair] {
        let data = Data(json.utf8)
        if let envelope = try? JSONDecoder().decode(PairsEnvelope.self, from: data) {
            return clean(envelope.pairs)
        }
        if let pairs = try? JSONDecoder().decode([PairDTO].self, from: data) {
            return clean(pairs)
        }
        return []
    }

    private static func clean(_ pairs: [PairDTO]) -> [OcrLayoutSerializer.LabelValuePair] {
        pairs.compactMap { pair in
            let label = pair.label.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = pair.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty, !value.isEmpty else { return nil }
            return OcrLayoutSerializer.LabelValuePair(label: label, value: value)
        }
    }

    private static func multiArrayOutput(from prediction: MLFeatureProvider) -> MLMultiArray? {
        let preferred = ["role_logits", "logits", "token_logits", "layout_logits"]
        for name in preferred {
            if let value = prediction.featureValue(for: name), value.type == .multiArray {
                return value.multiArrayValue
            }
        }
        for name in prediction.featureNames {
            guard let value = prediction.featureValue(for: name), value.type == .multiArray else { continue }
            return value.multiArrayValue
        }
        return nil
    }

    /// Decodes a simple block-role contract: class 1 = label, class 2 = value.
    /// Pair association follows model role sequence, not geometry-derived heuristics.
    private static func pairs(
        fromRoleLogits logits: MLMultiArray,
        blocks: [OcrLayoutSerializer.LayoutBlock]
    ) -> [OcrLayoutSerializer.LabelValuePair] {
        let shape = logits.shape.map(\.intValue)
        guard shape.count >= 2 else { return [] }
        let count = min(blocks.count, shape[shape.count - 2])
        let classes = shape[shape.count - 1]
        guard count > 0, classes >= 3 else { return [] }

        var pairs: [OcrLayoutSerializer.LabelValuePair] = []
        var pendingLabel: String?
        for index in 0 ..< count {
            let role = argmax(logits: logits, tokenIndex: index, classCount: classes)
            if role == 1 {
                pendingLabel = blocks[index].text
            } else if role == 2, let label = pendingLabel {
                pairs.append(OcrLayoutSerializer.LabelValuePair(label: label, value: blocks[index].text))
                pendingLabel = nil
            }
        }
        return pairs
    }

    private static func argmax(logits: MLMultiArray, tokenIndex: Int, classCount: Int) -> Int {
        var bestClass = 0
        var bestValue = -Double.greatestFiniteMagnitude
        for cls in 0 ..< classCount {
            let value = valueAt(logits, tokenIndex: tokenIndex, classIndex: cls)
            if value > bestValue {
                bestValue = value
                bestClass = cls
            }
        }
        return bestClass
    }

    private static func tokenIDs(
        for blocks: [OcrLayoutSerializer.LayoutBlock],
        description: MLFeatureDescription
    ) throws -> MLMultiArray {
        let array = try zeros(description: description)
        let limit = sequenceLength(from: description)
        for (index, block) in blocks.prefix(limit).enumerated() {
            array[index] = NSNumber(value: stableTokenID(for: block.text))
        }
        return array
    }

    private static func attentionMask(
        for blocks: [OcrLayoutSerializer.LayoutBlock],
        description: MLFeatureDescription
    ) throws -> MLMultiArray {
        let array = try zeros(description: description)
        let limit = min(sequenceLength(from: description), blocks.count)
        for index in 0 ..< limit {
            array[index] = 1
        }
        return array
    }

    private static func boundingBoxes(
        for blocks: [OcrLayoutSerializer.LayoutBlock],
        description: MLFeatureDescription
    ) throws -> MLMultiArray {
        let array = try zeros(description: description)
        let limit = min(sequenceLength(from: description), blocks.count)
        for index in 0 ..< limit {
            let block = blocks[index]
            let box = [
                Int((block.x * 1000).rounded()),
                Int((block.y * 1000).rounded()),
                Int(((block.x + block.width) * 1000).rounded()),
                Int(((block.y + block.height) * 1000).rounded()),
            ].map { min(1000, max(0, $0)) }
            for coordinate in 0 ..< 4 {
                setBBoxValue(array, tokenIndex: index, coordinateIndex: coordinate, value: box[coordinate])
            }
        }
        return array
    }

    private static func zeros(description: MLFeatureDescription) throws -> MLMultiArray {
        let shape = description.multiArrayConstraint?.shape
        let resolved = shape?.map { dimension in
            max(1, dimension.intValue)
        } ?? [1, 512]
        return try MLMultiArray(
            shape: resolved.map(NSNumber.init(value:)),
            dataType: description.multiArrayConstraint?.dataType ?? .float32
        )
    }

    private static func sequenceLength(from description: MLFeatureDescription) -> Int {
        let shape = description.multiArrayConstraint?.shape.map(\.intValue) ?? [1, 512]
        if shape.count >= 2 {
            return max(1, shape[shape.count - 2])
        }
        return max(1, shape.last ?? 512)
    }

    private static func stableTokenID(for text: String) -> Int32 {
        // Used only for CoreML exports that expose numeric ids without bundled tokenizer.
        // Production conversion should prefer the `ocr_json -> pairs_json` wrapper contract.
        let normalized = text.lowercased()
        let hash = normalized.utf8.reduce(UInt32(2166136261)) { partial, byte in
            (partial ^ UInt32(byte)) &* 16777619
        }
        return Int32(hash % 50_000) + 4
    }

    private static func valueAt(_ array: MLMultiArray, tokenIndex: Int, classIndex: Int) -> Double {
        let rank = array.shape.count
        if rank >= 3 {
            return array[
                [
                    NSNumber(value: 0),
                    NSNumber(value: tokenIndex),
                    NSNumber(value: classIndex),
                ]
            ].doubleValue
        }
        return array[
            [
                NSNumber(value: tokenIndex),
                NSNumber(value: classIndex),
            ]
        ].doubleValue
    }

    private static func setBBoxValue(
        _ array: MLMultiArray,
        tokenIndex: Int,
        coordinateIndex: Int,
        value: Int
    ) {
        let number = NSNumber(value: value)
        if array.shape.count >= 3 {
            array[
                [
                    NSNumber(value: 0),
                    NSNumber(value: tokenIndex),
                    NSNumber(value: coordinateIndex),
                ]
            ] = number
        } else {
            array[
                [
                    NSNumber(value: tokenIndex),
                    NSNumber(value: coordinateIndex),
                ]
            ] = number
        }
    }

    private static func ocrJSON(from blocks: [OcrLayoutSerializer.LayoutBlock]) -> String {
        let payload = blocks.map { block -> [String: Any] in
            [
                "text": block.text,
                "confidence": block.confidence,
                "bbox": [block.x, block.y, block.x + block.width, block.y + block.height],
            ]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: ["blocks": payload]),
              let json = String(data: data, encoding: .utf8)
        else { return #"{"blocks":[]}"# }
        return json
    }

    private static func statusReason(_ error: Error) -> String {
        let sanitized = String(
            String(describing: error)
            .lowercased()
            .map { char in
                char.isLetter || char.isNumber ? char : "_"
            }
        )
        let parts = sanitized.split(separator: "_")
        return parts.prefix(10).map(String.init).joined(separator: "_")
    }

    private enum AdapterError: Error, CustomStringConvertible {
        case unsupportedInput(String)
        case unsupportedOutput

        var description: String {
            switch self {
            case .unsupportedInput(let name): return "unsupported_input_\(name)"
            case .unsupportedOutput: return "unsupported_output_contract"
            }
        }
    }
}
