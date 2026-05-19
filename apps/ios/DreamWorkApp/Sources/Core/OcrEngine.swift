import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import UIKit
import Vision

/// High-quality on-device OCR built on Apple Vision with ID-aware tuning.
enum OcrEngine {
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    private static let idDocumentCustomWords = [
        "DRIVER", "LICENSE", "LICENCE", "IDENTIFICATION", "PASSPORT", "TEXAS", "CALIFORNIA",
        "SOCIAL", "SECURITY", "ADMINISTRATION", "SSN", "DOB", "ISS", "EXP", "DL", "NONE",
        "LIMITED", "TERM", "FLORIDA", "NEW YORK", "GEORGIA", "VETERAN", "ORGAN", "DONOR",
    ]

    private struct RecognizedLine: Hashable {
        let text: String
        let confidence: Float
        let bounds: CGRect

        var score: Int {
            OcrEngine.scoreCandidate(text) + Int(confidence * 40)
        }
    }

    static func recognizeText(from images: [CGImage]) async throws -> String {
        var sections: [String] = []
        for image in images {
            let text = try recognizeText(on: image)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                sections.append(trimmed)
            }
        }
        return sections.joined(separator: "\n\n")
    }

    static func recognizePageBlocks(from cgImage: CGImage) async throws -> [VisionOcrAdapter.TextBlock] {
        let lines = try collectLines(on: cgImage)
        return lines.map { line in
            VisionOcrAdapter.TextBlock(
                text: line.text,
                confidence: line.confidence,
                bounds: VisionOcrAdapter.NormRect(
                    x: Float(line.bounds.minX),
                    y: Float(line.bounds.minY),
                    width: Float(line.bounds.width),
                    height: Float(line.bounds.height)
                )
            )
        }
    }

    // MARK: - Core pipeline

    private static func recognizeText(on image: CGImage) throws -> String {
        let lines = try collectLines(on: image)
        return lines.map(\.text).joined(separator: "\n")
    }

    private static func collectLines(on image: CGImage) throws -> [RecognizedLine] {
        let ctx = ciContext
        let primary = preprocess(image, context: ctx) ?? image
        var batches: [[RecognizedLine]] = []

        batches.append(try recognizeLines(on: primary, minimumTextHeight: 0.008, usesLanguageCorrection: true))

        let highContrast = preprocess(
            image,
            context: ctx,
            scale: adaptiveScale(for: image) * 1.15,
            contrast: 1.65,
            brightness: 0.04,
            sharpness: 0.85
        ) ?? primary
        batches.append(try recognizeLines(on: highContrast, minimumTextHeight: 0.006, usesLanguageCorrection: false))

        if !containsZipOrCityStateZip(mergedText(batches)) {
            for crop in cropCandidatesForAddressRegion(primary) {
                let enhanced = preprocessBinarized(crop, context: ctx) ?? crop
                batches.append(try recognizeLines(
                    on: enhanced,
                    minimumTextHeight: 0.004,
                    usesLanguageCorrection: false
                ))
            }
        }

        if !containsNameLikeLine(mergedText(batches)) {
            for crop in cropCandidatesForNameRegion(primary) {
                let enhanced = preprocess(crop, context: ctx, scale: 2.2, contrast: 1.5, brightness: 0.03, sharpness: 0.75) ?? crop
                batches.append(try recognizeLines(
                    on: enhanced,
                    minimumTextHeight: 0.004,
                    usesLanguageCorrection: true
                ))
            }
        }

        return mergeRecognizedLines(batches)
    }

    private static func recognizeLines(
        on cgImage: CGImage,
        minimumTextHeight: Float,
        usesLanguageCorrection: Bool
    ) throws -> [RecognizedLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = usesLanguageCorrection
        request.recognitionLanguages = ["en-US"]
        request.minimumTextHeight = minimumTextHeight
        request.customWords = idDocumentCustomWords

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        return (request.results ?? []).compactMap { observation -> RecognizedLine? in
            guard let candidate = bestCandidate(from: observation) else { return nil }
            let cleaned = OcrTextPostProcessor.cleanLine(candidate.text)
            guard !cleaned.isEmpty else { return nil }
            return RecognizedLine(
                text: cleaned,
                confidence: candidate.confidence,
                bounds: observation.boundingBox
            )
        }
    }

    private struct ScoredCandidate {
        let text: String
        let confidence: Float
    }

    private static func bestCandidate(from observation: VNRecognizedTextObservation) -> ScoredCandidate? {
        let candidates = observation.topCandidates(8)
        guard !candidates.isEmpty else { return nil }

        let best = candidates.max { lhs, rhs in
            let left = scoreCandidate(lhs.string) + Int(lhs.confidence * 40)
            let right = scoreCandidate(rhs.string) + Int(rhs.confidence * 40)
            return left < right
        }

        guard let best else { return nil }
        let trimmed = best.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return ScoredCandidate(text: trimmed, confidence: best.confidence)
    }

    private static func scoreCandidate(_ raw: String) -> Int {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Int.min }

        var score = trimmed.count
        if trimmed.range(of: #"\d"#, options: .regularExpression) != nil { score += 12 }
        if trimmed.range(of: #"\d{2}/\d{2}/\d{4}"#, options: .regularExpression) != nil { score += 25 }
        if trimmed.range(of: #"\d{3}-\d{2}-\d{4}"#, options: .regularExpression) != nil { score += 30 }
        if trimmed.range(of: #"(?i)\b(DL|DOB|ISS|EXP|DRIVER|LICENSE|TEXAS|SOCIAL|SECURITY|SSN)\b"#, options: .regularExpression) != nil {
            score += 18
        }
        if trimmed.range(of: #"(?i)^texass?$"#, options: .regularExpression) != nil { score -= 60 }
        if trimmed.range(of: #"[А-Яа-яЁё]"#, options: .regularExpression) != nil { score -= 80 }
        if trimmed.filter({ !$0.isASCII }).count > trimmed.count / 3 { score -= 40 }
        return score
    }

    // MARK: - Merge & ordering

    private static func mergeRecognizedLines(_ batches: [[RecognizedLine]]) -> [RecognizedLine] {
        var kept: [RecognizedLine] = []

        for batch in batches {
            for line in batch {
                let key = normalizeLineKey(line.text)
                if let idx = kept.firstIndex(where: { normalizeLineKey($0.text) == key }) {
                    if line.score > kept[idx].score {
                        kept[idx] = line
                    }
                    continue
                }
                if kept.contains(where: { isNearDuplicate(line.text, $0.text) }) {
                    if let idx = kept.firstIndex(where: { isNearDuplicate(line.text, $0.text) }),
                       line.score > kept[idx].score
                    {
                        kept[idx] = line
                    }
                    continue
                }
                kept.append(line)
            }
        }

        return sortSpatially(kept)
    }

    private static func sortSpatially(_ lines: [RecognizedLine]) -> [RecognizedLine] {
        lines.sorted { lhs, rhs in
            let rowTolerance: CGFloat = 0.025
            if abs(lhs.bounds.midY - rhs.bounds.midY) > rowTolerance {
                return lhs.bounds.midY > rhs.bounds.midY
            }
            return lhs.bounds.minX < rhs.bounds.minX
        }
    }

    private static func normalizeLineKey(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: #"[^\w\s/\-]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isNearDuplicate(_ a: String, _ b: String) -> Bool {
        let na = normalizeLineKey(a)
        let nb = normalizeLineKey(b)
        if na == nb { return true }
        if na.count >= 4, nb.count >= 4 {
            if na.contains(nb) || nb.contains(na) { return true }
        }
        return false
    }

    private static func mergedText(_ batches: [[RecognizedLine]]) -> String {
        mergeRecognizedLines(batches).map(\.text).joined(separator: "\n")
    }

    // MARK: - Preprocessing

    private static func adaptiveScale(for image: CGImage) -> CGFloat {
        let longEdge = CGFloat(max(image.width, image.height))
        switch longEdge {
        case ..<900: return 2.4
        case ..<1400: return 2.0
        case ..<2200: return 1.65
        default: return 1.35
        }
    }

    private static func preprocess(_ image: CGImage, context: CIContext) -> CGImage? {
        preprocess(
            image,
            context: context,
            scale: adaptiveScale(for: image),
            contrast: 1.35,
            brightness: 0.02,
            sharpness: 0.55
        )
    }

    private static func preprocess(
        _ image: CGImage,
        context: CIContext,
        scale: CGFloat,
        contrast: CGFloat,
        brightness: CGFloat,
        sharpness: CGFloat
    ) -> CGImage? {
        let ci = CIImage(cgImage: image)

        let exposure = CIFilter.exposureAdjust()
        exposure.inputImage = ci
        exposure.ev = Float(0.15)

        let color = CIFilter.colorControls()
        color.inputImage = exposure.outputImage ?? ci
        color.saturation = 0.0
        color.contrast = Float(contrast)
        color.brightness = Float(brightness)

        let noise = CIFilter.noiseReduction()
        noise.inputImage = color.outputImage
        noise.noiseLevel = Float(0.02)
        noise.sharpness = Float(0.4)

        let sharpen = CIFilter.sharpenLuminance()
        sharpen.inputImage = noise.outputImage ?? color.outputImage
        sharpen.sharpness = Float(sharpness)

        let out = (sharpen.outputImage ?? noise.outputImage ?? color.outputImage ?? ci)
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return context.createCGImage(out, from: out.extent)
    }

    private static func preprocessBinarized(_ image: CGImage, context: CIContext) -> CGImage? {
        let ci = CIImage(cgImage: image)

        let color = CIFilter.colorControls()
        color.inputImage = ci
        color.saturation = 0.0
        color.contrast = 2.05
        color.brightness = 0.07

        let matrix = CIFilter.colorMatrix()
        matrix.inputImage = color.outputImage
        matrix.rVector = CIVector(x: 1.18, y: 0, z: 0, w: 0)
        matrix.gVector = CIVector(x: 0, y: 1.18, z: 0, w: 0)
        matrix.bVector = CIVector(x: 0, y: 0, z: 1.18, w: 0)
        matrix.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)

        let sharpen = CIFilter.sharpenLuminance()
        sharpen.inputImage = matrix.outputImage ?? color.outputImage
        sharpen.sharpness = 1.0

        let scale = max(adaptiveScale(for: image) * 1.8, 2.5)
        let out = (sharpen.outputImage ?? matrix.outputImage ?? color.outputImage ?? ci)
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return context.createCGImage(out, from: out.extent)
    }

    private static func cropCandidatesForAddressRegion(_ image: CGImage) -> [CGImage] {
        let w = CGFloat(image.width)
        let h = CGFloat(image.height)
        guard w > 2, h > 2 else { return [] }

        let rects: [CGRect] = [
            CGRect(x: 0, y: h * 0.28, width: w * 0.72, height: h * 0.42),
            CGRect(x: 0, y: h * 0.40, width: w * 0.74, height: h * 0.38),
            CGRect(x: 0, y: h * 0.44, width: w * 0.66, height: h * 0.24),
        ].map { $0.integral }

        return rects.compactMap { image.cropping(to: $0) }
    }

    private static func cropCandidatesForNameRegion(_ image: CGImage) -> [CGImage] {
        let w = CGFloat(image.width)
        let h = CGFloat(image.height)
        guard w > 2, h > 2 else { return [] }

        let rects: [CGRect] = [
            CGRect(x: 0, y: h * 0.52, width: w * 0.85, height: h * 0.38),
            CGRect(x: 0, y: h * 0.58, width: w * 0.80, height: h * 0.30),
        ].map { $0.integral }

        return rects.compactMap { image.cropping(to: $0) }
    }

    private static func containsZipOrCityStateZip(_ text: String) -> Bool {
        let upper = text.uppercased()
        if upper.range(of: #"\b\d{5}\b"#, options: .regularExpression) != nil { return true }
        if upper.range(of: #"\b[A-Z]{2}\s*\d{5}\b"#, options: .regularExpression) != nil { return true }
        if upper.range(of: #"\b[A-Z]{3,}\s+TX\s+\d{5}\b"#, options: .regularExpression) != nil { return true }
        return false
    }

    private static func containsNameLikeLine(_ text: String) -> Bool {
        text
            .components(separatedBy: .newlines)
            .contains(where: { ScanFieldValidator.isPlausiblePersonName($0) || ScanFieldValidator.isPlausibleNameComponent($0) })
    }
}

/// Line-level OCR cleanup before field parsers run.
enum OcrTextPostProcessor {
    static func cleanLine(_ raw: String) -> String {
        var line = raw
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: #"^\s*[¿§•·]+\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^[^\p{L}\d]+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        line = line.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        line = fixStateTypos(line)
        line = fixDateTokens(in: line)
        return line.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func cleanFullText(_ raw: String) -> String {
        raw
            .components(separatedBy: .newlines)
            .map(cleanLine)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static func fixStateTypos(_ line: String) -> String {
        line.replacingOccurrences(
            of: #"(?i)\btexass\b"#,
            with: "TEXAS",
            options: .regularExpression
        )
    }

    private static func fixDateTokens(in line: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\d{1,2}[/-]\d{1,3}[/-]?\d{2,4}"#) else {
            return line
        }
        let range = NSRange(line.startIndex..., in: line)
        let matches = regex.matches(in: line, range: range)
        guard !matches.isEmpty else { return line }

        var output = line
        for match in matches.reversed() {
            guard let r = Range(match.range, in: output) else { continue }
            let token = String(output[r])
            let fixed = DriverLicenseParserSupport.normalizeOCRDateToken(token)
            if fixed != token {
                output.replaceSubrange(r, with: fixed)
            }
        }
        return output
    }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

extension UIImage {
    /// Applies EXIF orientation so OCR sees the document upright.
    func normalizedCGImage() -> CGImage? {
        if imageOrientation == .up, let cgImage { return cgImage }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let rendered = renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
        return rendered.cgImage
    }
}
