import Foundation

/// Minimal BERT WordPiece tokenizer driven by a bundled HuggingFace `tokenizer.json`.
struct BertWordPieceTokenizer {
    struct EncodedBatch {
        let inputIDs: [Int64]
        let attentionMask: [Int64]
        let tokenTypeIDs: [Int64]
        let sequenceLength: Int
    }

    private let vocab: [String: Int]
    private let idsToToken: [Int: String]
    private let clsTokenID: Int64
    private let sepTokenID: Int64
    private let padTokenID: Int64
    private let unkTokenID: Int64
    private let maxLength: Int
    private let doLowerCase: Bool

    init?(tokenizerURL: URL, maxLength: Int = 128) {
        guard let data = try? Data(contentsOf: tokenizerURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let model = root["model"] as? [String: Any],
              let rawVocab = model["vocab"] as? [String: Int]
        else { return nil }

        vocab = rawVocab
        idsToToken = Dictionary(uniqueKeysWithValues: rawVocab.map { ($1, $0) })
        self.maxLength = maxLength

        func tokenID(for content: String, fallback: Int64) -> Int64 {
            if let added = root["added_tokens"] as? [[String: Any]] {
                for entry in added {
                    guard let text = entry["content"] as? String,
                          let id = entry["id"] as? Int,
                          text == content
                    else { continue }
                    return Int64(id)
                }
            }
            return Int64(rawVocab[content] ?? Int(fallback))
        }

        clsTokenID = tokenID(for: "[CLS]", fallback: 101)
        sepTokenID = tokenID(for: "[SEP]", fallback: 102)
        padTokenID = tokenID(for: "[PAD]", fallback: 0)
        unkTokenID = tokenID(for: "[UNK]", fallback: 100)

        if let normalizer = root["normalizer"] as? [String: Any],
           let normalizers = normalizer["normalizers"] as? [[String: Any]] {
            doLowerCase = normalizers.contains { ($0["type"] as? String) == "Lowercase" }
        } else {
            doLowerCase = true
        }
    }

    func encode(_ text: String) -> EncodedBatch {
        let basic = basicTokens(from: text)
        var wordPieces: [String] = []
        for token in basic {
            wordPieces.append(contentsOf: wordPiece(for: token))
        }

        var ids: [Int64] = [clsTokenID]
        ids.append(contentsOf: wordPieces.map { Int64(vocab[$0] ?? Int(unkTokenID)) })
        ids.append(sepTokenID)

        if ids.count > maxLength {
            ids = Array(ids.prefix(maxLength - 1)) + [sepTokenID]
        }

        let seqLen = ids.count
        let padCount = maxLength - seqLen
        let paddedIDs = ids + Array(repeating: padTokenID, count: max(0, padCount))
        let attention = Array(repeating: Int64(1), count: seqLen)
            + Array(repeating: Int64(0), count: max(0, padCount))
        let tokenTypes = Array(repeating: Int64(0), count: maxLength)

        return EncodedBatch(
            inputIDs: paddedIDs,
            attentionMask: attention,
            tokenTypeIDs: tokenTypes,
            sequenceLength: min(seqLen, maxLength)
        )
    }

    private func basicTokens(from text: String) -> [String] {
        var normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if doLowerCase {
            normalized = normalized.lowercased()
        }
        normalized = normalized.replacingOccurrences(
            of: #"[\u0000-\u001F]"#,
            with: " ",
            options: .regularExpression
        )

        var tokens: [String] = []
        var current = ""
        for scalar in normalized.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                current.unicodeScalars.append(scalar)
            } else {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                if !CharacterSet.whitespacesAndNewlines.contains(scalar) {
                    tokens.append(String(scalar))
                }
            }
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }

    private func wordPiece(for token: String) -> [String] {
        if token.count > 200 {
            return [idsToToken[Int(unkTokenID)] ?? "[UNK]"]
        }
        if vocab[token] != nil {
            return [token]
        }

        var chars = Array(token)
        var start = 0
        var pieces: [String] = []
        while start < chars.count {
            var end = chars.count
            var found: String?
            while start < end {
                let substr = String(chars[start ..< end])
                let candidate = start == 0 ? substr : "##\(substr)"
                if vocab[candidate] != nil {
                    found = candidate
                    break
                }
                end -= 1
            }
            guard let piece = found else {
                return [idsToToken[Int(unkTokenID)] ?? "[UNK]"]
            }
            pieces.append(piece)
            start = end
        }
        return pieces
    }
}
