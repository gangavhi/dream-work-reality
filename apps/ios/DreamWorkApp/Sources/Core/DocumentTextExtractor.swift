import Foundation
import PDFKit
import UIKit
import Vision

/// Runs on-device Vision OCR on PDF pages or raster images, then persists normalized JSON via the injected ingest closure (Rust → SQLite `extraction_run`).
enum DocumentTextExtractor {
    struct Summary {
        let document: VisionOcrAdapter.NormalizedDocument
        let pageCount: Int
        let blockCount: Int
    }

    enum ExtractError: LocalizedError {
        case unsupportedFile
        case imageDecodeFailed
        case pdfInvalidOrEmpty
        case visionFailed(Error)
        case rustRejected
        case noTextLayersFound

        var errorDescription: String? {
            switch self {
            case .unsupportedFile:
                return "Choose a PDF or image (JPEG, PNG, HEIC, etc.)."
            case .imageDecodeFailed:
                return "Could not read image data from the file."
            case .pdfInvalidOrEmpty:
                return "PDF could not be opened or has no pages."
            case .visionFailed(let err):
                return "Text recognition failed: \(err.localizedDescription)"
            case .rustRejected:
                return "Rust core rejected the OCR payload (invalid JSON?)."
            case .noTextLayersFound:
                return "No pages could be rasterized for OCR."
            }
        }
    }

    /// Maximum PDF pages to OCR per import (memory / latency guard).
    private static let maxPdfPages = 25
    /// Long edge cap for rendered PDF pages (points).
    private static let maxPdfRasterSide: CGFloat = 4096
    /// Minimum Vision average confidence before we lean on embedded PDF text layers.
    private static let lowVisionConfidenceThreshold: Float = 0.72

    /// - Parameter ingest: Returns whether SQLite ingest succeeded (`dreamwork_ocr_apply_normalized_json`).
    static func extractAndPersist(from url: URL, ingest: (String) -> Bool) async throws -> Summary {
        guard let kind = DocumentImportHelper.contentKind(for: url) else {
            throw ExtractError.unsupportedFile
        }

        let pages: [VisionOcrAdapter.Page]
        switch kind {
        case .pdf:
            pages = try await extractPdfPages(url: url)
        case .raster:
            pages = try await extractRasterPages(url: url)
        }

        guard !pages.isEmpty else {
            throw ExtractError.noTextLayersFound
        }

        let doc = VisionOcrAdapter.NormalizedDocument(pages: pages)
        guard let json = VisionOcrAdapter.encodeNormalizedDocumentJSON(doc), ingest(json) else {
            throw ExtractError.rustRejected
        }

        let blocks = pages.reduce(0) { $0 + $1.blocks.count }
        return Summary(document: doc, pageCount: pages.count, blockCount: blocks)
    }

    private static func extractRasterPages(url: URL) async throws -> [VisionOcrAdapter.Page] {
        let data = try Data(contentsOf: url)
        guard let uiImage = UIImage(data: data) else {
            throw ExtractError.imageDecodeFailed
        }
        let cgImage = uiImage.normalizedCGImage() ?? uiImage.cgImage
        guard let cgImage else {
            throw ExtractError.imageDecodeFailed
        }
        let page = try await recognizePage(cgImage: cgImage)
        return [page]
    }

    private static func extractPdfPages(url: URL) async throws -> [VisionOcrAdapter.Page] {
        guard let document = PDFDocument(url: url), document.pageCount > 0 else {
            throw ExtractError.pdfInvalidOrEmpty
        }

        let limit = min(document.pageCount, maxPdfPages)
        var pages: [VisionOcrAdapter.Page] = []

        for index in 0 ..< limit {
            guard let pdfPage = document.page(at: index) else { continue }
            let bounds = pdfPage.bounds(for: .mediaBox)
            guard bounds.width > 1, bounds.height > 1 else { continue }

            let longEdge = max(bounds.width, bounds.height)
            let scale = min(maxPdfRasterSide / longEdge, 6.5)
            let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            guard let cgImage = renderPdfPage(pdfPage, size: size) else { continue }
            var page = try await recognizePage(cgImage: cgImage)
            if let embedded = pdfPage.string?.trimmingCharacters(in: .whitespacesAndNewlines),
               !embedded.isEmpty
            {
                page = mergeEmbeddedPdfText(into: page, embedded: embedded)
            }
            pages.append(page)
        }

        guard !pages.isEmpty else {
            throw ExtractError.noTextLayersFound
        }
        return pages
    }

    private static func textPage(from text: String) -> VisionOcrAdapter.Page {
        VisionOcrAdapter.Page(blocks: [
            VisionOcrAdapter.TextBlock(
                text: text,
                confidence: 1.0,
                bounds: VisionOcrAdapter.NormRect(x: 0, y: 0, width: 1, height: 0.1)
            ),
        ])
    }

    private static func recognizePage(cgImage: CGImage) async throws -> VisionOcrAdapter.Page {
        let blocks = try await OcrEngine.recognizePageBlocksWithFallback(from: cgImage)
        return VisionOcrAdapter.Page(blocks: blocks)
    }

    /// Renders a PDF page at full resolution (sharper than `PDFPage.thumbnail` for scanned IDs).
    private static func renderPdfPage(_ pdfPage: PDFPage, size: CGSize) -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            ctx.cgContext.saveGState()
            let bounds = pdfPage.bounds(for: .mediaBox)
            let sx = size.width / max(bounds.width, 1)
            let sy = size.height / max(bounds.height, 1)
            ctx.cgContext.scaleBy(x: sx, y: sy)
            pdfPage.draw(with: .mediaBox, to: ctx.cgContext)
            ctx.cgContext.restoreGState()
        }
        return image.cgImage
    }

    /// Merges OmniPage / PDFKit text layers with Vision blocks (common on scanned passport PDFs).
    private static func mergeEmbeddedPdfText(
        into page: VisionOcrAdapter.Page,
        embedded: String
    ) -> VisionOcrAdapter.Page {
        guard shouldMergeEmbeddedPdfText(page: page, embedded: embedded) else { return page }

        let embeddedLines = OcrTextPostProcessor.cleanFullText(embedded)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                guard line.count >= 2 else { return false }
                let letters = line.filter(\.isLetter).count
                return letters >= 2 || line.range(of: #"\d{4,}"#, options: .regularExpression) != nil
            }

        guard !embeddedLines.isEmpty else { return page }

        var merged = page.blocks
        var y: Float = 0.98
        for line in embeddedLines {
            if merged.contains(where: { isDuplicateOcrLine($0.text, line) }) { continue }
            merged.append(
                VisionOcrAdapter.TextBlock(
                    text: line,
                    confidence: page.blocks.isEmpty ? 0.92 : 0.84,
                    bounds: VisionOcrAdapter.NormRect(x: 0.02, y: y, width: 0.96, height: 0.02)
                )
            )
            y = max(0, y - 0.018)
        }
        return VisionOcrAdapter.Page(blocks: merged)
    }

    private static func isDuplicateOcrLine(_ existing: String, _ candidate: String) -> Bool {
        let a = normalizeOcrLineKey(existing)
        let b = normalizeOcrLineKey(candidate)
        if a == b { return true }
        if a.count >= 5, b.count >= 5, (a.contains(b) || b.contains(a)) { return true }
        return false
    }

    private static func shouldMergeEmbeddedPdfText(page: VisionOcrAdapter.Page, embedded: String) -> Bool {
        if page.blocks.isEmpty { return true }
        let visionAverage = PaddleOcrAdapter.averageConfidence(page.blocks)
        if visionAverage < lowVisionConfidenceThreshold { return true }
        if page.blocks.count < 8 { return true }

        let visionText = page.blocks.map(\.text).joined(separator: "\n").uppercased()
        let embeddedUpper = embedded.uppercased()
        let embeddedLooksIndianPassport = embeddedUpper.contains("REPUBLIC OF INDIA")
            || embeddedUpper.contains("P<IND")
            || embeddedUpper.contains("PASSPORT")
        if embeddedLooksIndianPassport,
           visionText.range(of: #"\b[MN][0-9OQKIL]{6,8}\b"#, options: .regularExpression) == nil
        {
            return true
        }
        if embeddedUpper.contains("PIN"), !visionText.contains("PIN") {
            return true
        }
        return false
    }

    private static func normalizeOcrLineKey(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: #"[^\p{L}\d]"#, with: "", options: .regularExpression)
    }
}
