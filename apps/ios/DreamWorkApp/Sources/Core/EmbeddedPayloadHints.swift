import Foundation
import PDFKit
import UIKit
import Vision

/// Optional machine-readable payloads (barcode, MRZ) as hints — not document-type routing.
enum EmbeddedPayloadHints {
    struct Result: Hashable {
        var barcodePayloads: [String]
        var mrzLines: [String]

        static let empty = Result(barcodePayloads: [], mrzLines: [])

        var promptAppendix: String? {
            var lines: [String] = []
            if !barcodePayloads.isEmpty {
                lines.append("## Embedded barcode payload(s)")
                for (index, payload) in barcodePayloads.enumerated() {
                    lines.append("Barcode \(index + 1):\n\(payload)")
                }
            }
            if !mrzLines.isEmpty {
                lines.append("## Machine-readable zone (MRZ) lines")
                lines.append(contentsOf: mrzLines)
            }
            guard !lines.isEmpty else { return nil }
            return lines.joined(separator: "\n")
        }
    }

    static func collect(
        fileURL: URL?,
        layoutText: String
    ) async -> Result {
        var barcodePayloads: [String] = []
        if let fileURL {
            barcodePayloads = (try? await detectBarcodes(from: fileURL)) ?? []
        }
        let mrzLines = detectMRZLines(in: layoutText)
        return Result(barcodePayloads: barcodePayloads, mrzLines: mrzLines)
    }

    private static func detectBarcodes(from url: URL) async throws -> [String] {
        let images = try rasterCGImages(from: url)
        guard !images.isEmpty else { return [] }
        return try Barcode.detectPayloads(in: images)
    }

    private static func detectMRZLines(in text: String) -> [String] {
        text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                let upper = line.uppercased()
                guard line.count >= 28, line.count <= 96 else { return false }
                let angleCount = line.filter { $0 == "<" }.count
                return upper.hasPrefix("P<") || angleCount >= 12
            }
    }

    private static func rasterCGImages(from url: URL) throws -> [CGImage] {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" {
            guard let doc = PDFDocument(url: url) else { return [] }
            return renderPDFPages(doc, maxPages: 3)
        }
        let data = try Data(contentsOf: url)
        guard let uiImage = UIImage(data: data),
              let cg = uiImage.normalizedCGImage() ?? uiImage.cgImage
        else {
            return []
        }
        return [cg]
    }

    private static func renderPDFPages(_ doc: PDFDocument, maxPages: Int) -> [CGImage] {
        let count = min(doc.pageCount, maxPages)
        var images: [CGImage] = []
        for index in 0 ..< count {
            guard let page = doc.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let scale: CGFloat = 2.0
            let width = Int(bounds.width * scale)
            let height = Int(bounds.height * scale)
            guard width > 0, height > 0 else { continue }
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
            let uiImage = renderer.image { ctx in
                UIColor.white.setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
                ctx.cgContext.translateBy(x: 0, y: CGFloat(height))
                ctx.cgContext.scaleBy(x: scale, y: -scale)
                page.draw(with: .mediaBox, to: ctx.cgContext)
            }
            if let cg = uiImage.cgImage {
                images.append(cg)
            }
        }
        return images
    }
}
