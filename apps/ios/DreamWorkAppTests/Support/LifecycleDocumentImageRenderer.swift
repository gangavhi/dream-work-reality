import UIKit

/// Renders synthetic document text to a PNG for Vision OCR on the iOS Simulator.
enum LifecycleDocumentImageRenderer {
    static func pngURL(from lines: [String], filename: String) throws -> URL {
        let font = UIFont.monospacedSystemFont(ofSize: 26, weight: .regular)
        let lineHeight: CGFloat = 36
        let width: CGFloat = 1400
        let height = max(400, CGFloat(lines.count) * lineHeight + 48)

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))

            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byTruncatingTail

            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.black,
                .paragraphStyle: paragraph,
            ]

            for (index, line) in lines.enumerated() {
                let y = 24 + CGFloat(index) * lineHeight
                (line as NSString).draw(
                    in: CGRect(x: 28, y: y, width: width - 56, height: lineHeight),
                    withAttributes: attributes
                )
            }
        }

        guard let data = image.pngData() else {
            throw NSError(domain: "LifecycleDocumentImageRenderer", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to encode PNG",
            ])
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return url
    }
}
