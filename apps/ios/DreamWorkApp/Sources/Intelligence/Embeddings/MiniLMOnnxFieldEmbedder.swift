import Foundation

/// ONNX Runtime wrapper for `sentence-transformers/all-MiniLM-L6-v2` INT8 (~23 MB).
final class MiniLMOnnxFieldEmbedder: @unchecked Sendable {
    static let shared = MiniLMOnnxFieldEmbedder()

    static let artifactID = "embed.minilm.v1"
    static let hiddenSize = 384

    private let lock = NSLock()
    private var env: ORTEnv?
    private var session: ORTSession?
    private var tokenizer: BertWordPieceTokenizer?
    private var loadError: String?
    private var inputNames: [String] = []
    private var outputNames: [String] = []

    private init() {}

    var isAvailable: Bool {
        lock.lock()
        defer { lock.unlock() }
        if session != nil { return true }
        try? ensureLoadedLocked()
        return session != nil
    }

    var statusToken: String {
        lock.lock()
        defer { lock.unlock() }
        if session != nil {
            return "\(Self.artifactID):onnx:int8:loaded"
        }
        if let loadError {
            return "\(Self.artifactID):onnx:missing:\(loadError)"
        }
        return "\(Self.artifactID):onnx:not_loaded"
    }

    func embed(_ text: String) -> [Float]? {
        lock.lock()
        defer { lock.unlock() }
        do {
            try ensureLoadedLocked()
            guard let session, let tokenizer else { return nil }

            let encoded = tokenizer.encode(text)
            let shape: [NSNumber] = [1, NSNumber(value: encoded.inputIDs.count)]
            let inputIDs = try makeInt64Tensor(encoded.inputIDs, shape: shape)
            let attention = try makeInt64Tensor(encoded.attentionMask, shape: shape)
            let tokenTypes = try makeInt64Tensor(encoded.tokenTypeIDs, shape: shape)

            var inputs: [String: ORTValue] = [:]
            for name in inputNames {
                switch name {
                case "input_ids": inputs[name] = inputIDs
                case "attention_mask": inputs[name] = attention
                case "token_type_ids": inputs[name] = tokenTypes
                default: break
                }
            }
            if inputs.isEmpty {
                inputs["input_ids"] = inputIDs
                inputs["attention_mask"] = attention
                inputs["token_type_ids"] = tokenTypes
            }

            let outputs = try session.run(
                withInputs: inputs,
                outputNames: Set(outputNames),
                runOptions: nil
            )
            guard let firstOutput = outputs.values.first else { return nil }

            let info = try firstOutput.tensorTypeAndShapeInfo()
            let data = try firstOutput.tensorData() as Data
            let floats: [Float] = data.withUnsafeBytes { raw in
                Array(raw.bindMemory(to: Float.self))
            }

            let dims = info.shape.map(\.intValue)
            guard dims.count == 3, dims[2] == Self.hiddenSize else {
                loadError = "unexpected_output_shape"
                return nil
            }
            let seqLen = min(encoded.sequenceLength, dims[1])
            var pooled = meanPool(
                hidden: floats,
                seqLen: seqLen,
                hiddenSize: Self.hiddenSize,
                attentionMask: encoded.attentionMask
            )
            l2Normalize(&pooled)
            return pooled
        } catch {
            loadError = error.localizedDescription
            return nil
        }
    }

    func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Double = 0
        for i in a.indices {
            dot += Double(a[i]) * Double(b[i])
        }
        return dot
    }

    // MARK: - Private

    private func ensureLoadedLocked() throws {
        if session != nil { return }

        guard let modelPath = BundledModelStore.fieldEmbedderOnnxPath() else {
            loadError = "model_or_tokenizer_missing"
            throw EmbedderError.missingArtifact
        }
        let tokenizerURL = URL(fileURLWithPath: modelPath).deletingLastPathComponent()
            .appendingPathComponent("minilm_tokenizer.json")
        guard FileManager.default.fileExists(atPath: tokenizerURL.path),
              let parsedTokenizer = BertWordPieceTokenizer(tokenizerURL: tokenizerURL)
        else {
            loadError = "tokenizer_missing"
            throw EmbedderError.missingArtifact
        }

        let environment = try ORTEnv(loggingLevel: .warning)
        let options = try ORTSessionOptions()
        _ = try options.setIntraOpNumThreads(1)
        let ortSession = try ORTSession(env: environment, modelPath: modelPath, sessionOptions: options)

        env = environment
        session = ortSession
        tokenizer = parsedTokenizer
        inputNames = try ortSession.inputNames()
        outputNames = try ortSession.outputNames()
        loadError = nil
    }

    private func makeInt64Tensor(_ values: [Int64], shape: [NSNumber]) throws -> ORTValue {
        var mutable = values
        let byteCount = mutable.count * MemoryLayout<Int64>.size
        let data = mutable.withUnsafeMutableBytes { Data($0) }
        return try ORTValue(
            tensorData: NSMutableData(data: data),
            elementType: .int64,
            shape: shape
        )
    }

    private func meanPool(
        hidden: [Float],
        seqLen: Int,
        hiddenSize: Int,
        attentionMask: [Int64]
    ) -> [Float] {
        var sum = [Float](repeating: 0, count: hiddenSize)
        var count: Float = 0
        for index in 0 ..< seqLen {
            guard index < attentionMask.count, attentionMask[index] == 1 else { continue }
            count += 1
            let offset = index * hiddenSize
            for dim in 0 ..< hiddenSize {
                sum[dim] += hidden[offset + dim]
            }
        }
        guard count > 0 else { return sum }
        let inv = 1 / count
        return sum.map { $0 * inv }
    }

    private func l2Normalize(_ vector: inout [Float]) {
        let norm = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        guard norm > 0 else { return }
        for index in vector.indices {
            vector[index] /= norm
        }
    }

    private enum EmbedderError: Error {
        case missingArtifact
    }
}
