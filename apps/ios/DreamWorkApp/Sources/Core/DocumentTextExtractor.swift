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
    /// Long edge cap for rendered PDF thumbnails (points).
    private static let maxPdfRasterSide: CGFloat = 2048

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
        guard let uiImage = UIImage(data: data), let cgImage = uiImage.cgImage else {
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
            let scale = min(maxPdfRasterSide / longEdge, 3.0)
            let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            let thumbnail = pdfPage.thumbnail(of: size, for: .mediaBox)
            guard let cgImage = thumbnail.cgImage else { continue }
            var page = try await recognizePage(cgImage: cgImage)
            if page.blocks.isEmpty, let embedded = pdfPage.string?.trimmingCharacters(in: .whitespacesAndNewlines),
               !embedded.isEmpty
            {
                page = textPage(from: embedded)
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
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.recognitionLanguages = ["en-US"]
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([request])
                    let observations = request.results ?? []
                    let partial = VisionOcrAdapter.normalizedDocument(from: observations)
                    let page = partial.pages.first ?? VisionOcrAdapter.Page(blocks: [])
                    continuation.resume(returning: page)
                } catch {
                    continuation.resume(throwing: ExtractError.visionFailed(error))
                }
            }
        }
    }
}
