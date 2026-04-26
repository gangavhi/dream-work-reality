import Foundation
import SwiftUI
import Vision
import VisionKit
import UniformTypeIdentifiers
import PDFKit
import CoreImage
import CoreImage.CIFilterBuiltins

struct DriverLicenseScanResult: Sendable {
    var fullName: String?
    var firstName: String?
    var lastName: String?
    var dateOfBirth: Date?
    var documentNumber: String?
    var issueDate: Date?
    var expiryDate: Date?
    var addressLine1: String?
    var city: String?
    var state: String?
    var postalCode: String?
    var height: String?
    var eyeColor: String?
    var genAIValues: [String: String]?
    var rawText: String
}

@MainActor
private enum DriverLicenseScannerPipeline {
    static func scan(images: [CGImage]) async throws -> DriverLicenseScanResult {
        // Prefer PDF417 (AAMVA) barcode payload when available; it is much more reliable than OCR.
        guard !images.isEmpty else {
            throw NSError(domain: "DriverLicenseScanner", code: 11, userInfo: [NSLocalizedDescriptionKey: "No images to scan"])
        }
        // Some imports (screenshots, compressed images, PDFs) make barcode detection flaky.
        // Try all pages/images and an enhanced pass.
        let barcodePayloads = (try? Barcode.detectPayloads(in: images)) ?? []
        let barcodeParsed: DriverLicenseScanResult? = barcodePayloads
            .compactMap { DriverLicenseParser.parseAAMVAPDF417($0) }
            .first

        let rawText = try await OCR.recognizeText(from: images)
        let ocrParsed = DriverLicenseParser.parse(rawText)

        // Optional "GenAI" extraction: send BOTH OCR text and (if present) barcode payloads.
        // This makes extraction reliable even when the photo is blurry but barcode is readable,
        // or when barcode is missing but OCR is readable.
        let genAIInput = (barcodePayloads.isEmpty ? rawText : "\(barcodePayloads.joined(separator: "\n"))\n\n\(rawText)")
        let genAIParsed = await GenAI.extractDriverLicense(from: genAIInput)

        // Build the profile primarily from GenAI-extracted fields when available.
        // This ensures profile creation uses the best/most-robust mapping.
        let base = genAIParsed ?? barcodeParsed ?? ocrParsed
        var merged = base
        if let barcodeParsed {
            merged = DriverLicenseParser.merge(primary: merged, fallback: barcodeParsed)
        }
        merged = DriverLicenseParser.merge(primary: merged, fallback: ocrParsed)

        if !barcodePayloads.isEmpty {
            merged.rawText = "BARCODE:\n\(barcodePayloads.joined(separator: "\n---\n"))\n\nOCR:\n\(rawText)"
        } else {
            merged.rawText = rawText
        }
        if let genAIParsed {
            merged.rawText += "\n\nGENAI_EXTRACTED:\n" + summarize(genAIParsed)
        }
        return merged
    }

    private static func summarize(_ r: DriverLicenseScanResult) -> String {
        [
            "Full: \(r.fullName ?? "—")",
            "First: \(r.firstName ?? "—")",
            "Last: \(r.lastName ?? "—")",
            "DOB: \(r.dateOfBirth.map { dfMMDDYYYY().string(from: $0) } ?? "—")",
            "DL#: \(r.documentNumber ?? "—")",
            "Issue: \(r.issueDate.map { dfMMDDYYYY().string(from: $0) } ?? "—")",
            "Expiry: \(r.expiryDate.map { dfMMDDYYYY().string(from: $0) } ?? "—")",
            "Addr: \(r.addressLine1 ?? "—")",
            "City: \(r.city ?? "—")",
            "State: \(r.state ?? "—")",
            "ZIP: \(r.postalCode ?? "—")",
            "Height: \(r.height ?? "—")",
            "Eyes: \(r.eyeColor ?? "—")",
        ].joined(separator: "\n")
    }

    private static func dfMMDDYYYY() -> DateFormatter {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "MM/dd/yyyy"
        return df
    }

    static func scan(imageData: Data) async throws -> DriverLicenseScanResult {
        guard let uiImage = UIImage(data: imageData) else {
            throw NSError(domain: "DriverLicenseScanner", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unable to read image"])
        }
        guard let cg = makeCGImage(from: uiImage) else {
            throw NSError(domain: "DriverLicenseScanner", code: 12, userInfo: [NSLocalizedDescriptionKey: "Unable to decode image for OCR"])
        }
        return try await scan(images: [cg])
    }

    static func scan(fileURL url: URL) async throws -> DriverLicenseScanResult {
        let images = try loadImagesForOCR(from: url)
        if images.isEmpty {
            throw NSError(domain: "DriverLicenseScanner", code: 8, userInfo: [NSLocalizedDescriptionKey: "PDF had no readable pages"])
        }
        return try await scan(images: images)
    }

    static func scan(remoteURL url: URL) async throws -> DriverLicenseScanResult {
        let (data, response) = try await URLSession.shared.data(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(status) else {
            throw NSError(domain: "DriverLicenseScanner", code: 4, userInfo: [NSLocalizedDescriptionKey: "HTTP \(status)"])
        }

        let ext = url.pathExtension.lowercased()
        if ext == "pdf" {
            guard let doc = PDFDocument(data: data) else {
                throw NSError(domain: "DriverLicenseScanner", code: 7, userInfo: [NSLocalizedDescriptionKey: "Unable to read PDF"])
            }
            let images = renderPDF(doc)
            if images.isEmpty {
                throw NSError(domain: "DriverLicenseScanner", code: 8, userInfo: [NSLocalizedDescriptionKey: "PDF had no readable pages"])
            }
            return try await scan(images: images)
        }

        return try await scan(imageData: data)
    }

    private static func loadImagesForOCR(from url: URL) throws -> [CGImage] {
        let ext = url.pathExtension.lowercased()

        if ext == "pdf" {
            guard let doc = PDFDocument(url: url) else {
                throw NSError(domain: "DriverLicenseScanner", code: 7, userInfo: [NSLocalizedDescriptionKey: "Unable to read PDF"])
            }

            return renderPDF(doc)
        }

        let data = try Data(contentsOf: url)
        guard let uiImage = UIImage(data: data), let cg = makeCGImage(from: uiImage) else {
            throw NSError(domain: "DriverLicenseScanner", code: 9, userInfo: [NSLocalizedDescriptionKey: "Selected file is not a readable image"])
        }
        return [cg]
    }

    private static func makeCGImage(from uiImage: UIImage) -> CGImage? {
        if let cg = uiImage.cgImage { return cg }
        if let ci = uiImage.ciImage {
            let ctx = CIContext(options: nil)
            return ctx.createCGImage(ci, from: ci.extent)
        }
        // Last resort: render into a bitmap context.
        let size = uiImage.size
        if size.width <= 0 || size.height <= 0 { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let rendered = renderer.image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
            uiImage.draw(in: CGRect(origin: .zero, size: size))
        }
        return rendered.cgImage
    }

    private static func renderPDF(_ doc: PDFDocument) -> [CGImage] {
        var images: [CGImage] = []
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            if let cg = renderPDFPage(page) { images.append(cg) }
        }
        if images.isEmpty {
            // throw via caller
            return []
        }
        return images
    }

    private static func renderPDFPage(_ page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2.0
        let size = CGSize(width: max(1, bounds.width * scale), height: max(1, bounds.height * scale))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            ctx.cgContext.saveGState()
            ctx.cgContext.translateBy(x: 0, y: size.height)
            ctx.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: ctx.cgContext)
            ctx.cgContext.restoreGState()
        }

        return image.cgImage
    }
}

private enum GenAI {
    struct ExtractRequest: Encodable {
        var document_type: String
        var raw_text: String
    }

    struct ExtractResponse: Decodable {
        var values: [String: String]?
    }

    static func extractDriverLicense(from rawText: String) async -> DriverLicenseScanResult? {
        guard let url = URL(string: "http://127.0.0.1:18081/genai/extract-document") else { return nil }
        let body = ExtractRequest(document_type: "driver_license", raw_text: rawText)
        guard let payload = try? JSONEncoder().encode(body) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = payload
        request.timeoutInterval = 1.5

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            guard (200..<300).contains(status) else { return nil }
            let decoded = try JSONDecoder().decode(ExtractResponse.self, from: data)
            guard let v = decoded.values, !v.isEmpty else { return nil }

            func pick(_ keys: [String]) -> String? {
                for k in keys {
                    if let val = v[k]?.trimmingCharacters(in: .whitespacesAndNewlines), !val.isEmpty {
                        return val
                    }
                }
                return nil
            }

            // Map canonical keys to DriverLicenseScanResult.
            let r = DriverLicenseScanResult(
                fullName: pick(["full_name", "display_name", "full"]),
                firstName: pick(["first_name", "first"]),
                lastName: pick(["last_name", "last"]),
                dateOfBirth: parseDateMMDDYYYY(pick(["date_of_birth_mmddyyyy", "dob"])),
                documentNumber: pick(["document_number", "dl"]),
                issueDate: parseDateMMDDYYYY(pick(["issue_mmddyyyy", "issue"])),
                expiryDate: parseDateMMDDYYYY(pick(["expiry_mmddyyyy", "expiry"])),
                addressLine1: pick(["address_line_1", "addr"]),
                city: pick(["city", "city_name"]),
                state: pick(["state", "state_code"]),
                postalCode: pick(["postal_code", "zip"]),
                height: pick(["height", "hgt"]),
                eyeColor: pick(["eye_color", "eyes"]),
                genAIValues: v,
                rawText: rawText
            )
            return r
        } catch {
            return nil
        }
    }

    private static func parseDateMMDDYYYY(_ s: String?) -> Date? {
        guard let s else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Accept MM/dd/yyyy and also yyyy-mm-dd.
        let df1 = DateFormatter()
        df1.locale = Locale(identifier: "en_US_POSIX")
        df1.timeZone = TimeZone(secondsFromGMT: 0)
        df1.dateFormat = "MM/dd/yyyy"
        if let d = df1.date(from: trimmed) { return d }

        let df2 = DateFormatter()
        df2.locale = Locale(identifier: "en_US_POSIX")
        df2.timeZone = TimeZone(secondsFromGMT: 0)
        df2.dateFormat = "yyyy-MM-dd"
        if let d = df2.date(from: trimmed) { return d }

        // Accept yyyymmdd.
        let digits = trimmed.filter(\.isNumber)
        if digits.count == 8 {
            let yyyy = String(digits.prefix(4))
            let mm = String(digits.dropFirst(4).prefix(2))
            let dd = String(digits.dropFirst(6).prefix(2))
            return df1.date(from: "\(mm)/\(dd)/\(yyyy)")
        }

        return nil
    }
}

@MainActor
struct DriverLicenseScannerView: UIViewControllerRepresentable {
    let onResult: (Result<DriverLicenseScanResult, Error>) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        if VNDocumentCameraViewController.isSupported {
            let vc = VNDocumentCameraViewController()
            vc.delegate = context.coordinator
            return vc
        }

        // Fallback for Simulator: allow selecting an image and running on-device OCR.
        let fallback = UIHostingController(rootView: ScannerFallbackView(onResult: onResult))
        return fallback
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onResult: onResult)
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        private let onResult: (Result<DriverLicenseScanResult, Error>) -> Void

        init(onResult: @escaping (Result<DriverLicenseScanResult, Error>) -> Void) {
            self.onResult = onResult
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            Task { @MainActor in
                controller.dismiss(animated: true)
            }
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            Task { @MainActor in
                controller.dismiss(animated: true) {
                    self.onResult(.failure(error))
                }
            }
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let images: [CGImage] = (0..<scan.pageCount).compactMap { idx in
                scan.imageOfPage(at: idx).cgImage
            }

            Task { @MainActor in
                controller.dismiss(animated: true) {
                    Task {
                        do {
                            let parsed = try await DriverLicenseScannerPipeline.scan(images: images)
                            self.onResult(.success(parsed))
                        } catch {
                            self.onResult(.failure(error))
                        }
                    }
                }
            }
        }
    }
}

@MainActor
private struct ScannerFallbackView: View {
    let onResult: (Result<DriverLicenseScanResult, Error>) -> Void

    private struct RemoteItem: Identifiable, Hashable {
        var id: String { url.absoluteString }
        let url: URL
        let display: String
    }

    @State private var isWorking = false
    @State private var isPresentingFilePicker = false
    @State private var dropHint: String?
#if targetEnvironment(simulator)
    @State private var isPresentingDownloadsPicker = false
    @State private var downloadsItems: [RemoteItem] = []
    @State private var downloadsError: String?
#endif

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Scan Document")
                    .font(.title2)

                Text("Choose a document to scan (or drag & drop a file from your Mac).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button {
#if targetEnvironment(simulator)
                    // Simulator: show Mac Downloads listing (served by scripts/serve_downloads.sh).
                    isPresentingDownloadsPicker = true
                    Task { await loadSimulatorDownloadsListing() }
#else
                    isPresentingFilePicker = true
#endif
                } label: {
                    HStack {
                        Text("Choose Document")
                        Spacer()
                        Image(systemName: "doc")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isWorking)
#if !targetEnvironment(simulator)
                .fileImporter(
                    isPresented: $isPresentingFilePicker,
                    allowedContentTypes: [
                        UTType.image,
                        UTType.heic,
                        UTType.pdf,
                        UTType.data,
                    ],
                    allowsMultipleSelection: false
                ) { result in
                    Task {
                        await handleFileImportResult(result)
                    }
                }
#endif

                if let dropHint {
                    Text(dropHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if isWorking {
                    ProgressView("Reading…")
                        .padding(.top, 8)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Scan")
            .navigationBarTitleDisplayMode(.inline)
#if targetEnvironment(simulator)
            .sheet(isPresented: $isPresentingDownloadsPicker) {
                NavigationStack {
                    List {
                        if let downloadsError {
                            Text(downloadsError)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        Section("Mac Downloads") {
                            ForEach(downloadsItems) { item in
                                Button(item.display) {
                                    Task { await scanRemote(url: item.url) }
                                }
                            }
                        }
                    }
                    .navigationTitle("Choose from Downloads")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { isPresentingDownloadsPicker = false }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Refresh") { Task { await loadSimulatorDownloadsListing() } }
                                .disabled(isWorking)
                        }
                    }
                }
            }
#endif
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: nil) { providers in
                guard !isWorking else { return false }
                guard let provider = providers.first else { return false }
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    Task { @MainActor in
                        do {
                            dropHint = nil
                            guard let data = item as? Data,
                                  let url = URL(dataRepresentation: data, relativeTo: nil)
                            else {
                                dropHint = "Drop failed: couldn’t read file URL."
                                return
                            }

                            if isWorking { return }
                            isWorking = true
                            defer { isWorking = false }

                            let didStart = url.startAccessingSecurityScopedResource()
                            defer {
                                if didStart { url.stopAccessingSecurityScopedResource() }
                            }

                            let parsed = try await DriverLicenseScannerPipeline.scan(fileURL: url)
                            onResult(.success(parsed))
                        } catch {
                            dropHint = "Drop scan failed: \(error.localizedDescription)"
                            onResult(.failure(error))
                        }
                    }
                }
                return true
            }
        }
    }

    private func handleFileImportResult(_ result: Result<[URL], Error>) async {
        if isWorking { return }
        isWorking = true
        defer { isWorking = false }

        do {
            let urls = try result.get()
            guard let url = urls.first else {
                throw NSError(domain: "DriverLicenseScanner", code: 6, userInfo: [NSLocalizedDescriptionKey: "No file selected"])
            }

            let didStart = url.startAccessingSecurityScopedResource()
            defer {
                if didStart { url.stopAccessingSecurityScopedResource() }
            }

            let parsed = try await DriverLicenseScannerPipeline.scan(fileURL: url)
            onResult(.success(parsed))
        } catch {
            onResult(.failure(error))
        }
    }

#if targetEnvironment(simulator)
    private func scanRemote(url: URL) async {
        if isWorking { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let parsed = try await DriverLicenseScannerPipeline.scan(remoteURL: url)
            isPresentingDownloadsPicker = false
            onResult(.success(parsed))
        } catch {
            downloadsError = "Scan failed: \(error.localizedDescription)"
            onResult(.failure(error))
        }
    }

    private func loadSimulatorDownloadsListing() async {
        if isWorking { return }
        isWorking = true
        defer { isWorking = false }

        // scripts/run_demo.sh starts scripts/serve_downloads.sh on 8009
        let baseURL = URL(string: "http://127.0.0.1:8009/")!
        do {
            let (data, response) = try await URLSession.shared.data(from: baseURL)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            guard (200..<300).contains(status) else {
                throw NSError(domain: "DriverLicenseScanner", code: 21, userInfo: [NSLocalizedDescriptionKey: "HTTP \(status)"])
            }
            let html = String(data: data, encoding: .utf8) ?? ""
            downloadsItems = parsePythonHTTPServerListing(html: html, baseURL: baseURL)
            downloadsError = downloadsItems.isEmpty ? "No supported files found in Downloads." : nil
        } catch {
            downloadsItems = []
            downloadsError = """
            Couldn’t load Mac Downloads.
            Make sure the server is running: `./scripts/run_demo.sh` (or `./scripts/serve_downloads.sh 8009`)
            Error: \(error.localizedDescription)
            """
        }
    }

    private func parsePythonHTTPServerListing(html: String, baseURL: URL) -> [RemoteItem] {
        let pattern = #"href="([^"]+)""#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }

        let ns = html as NSString
        let matches = re.matches(in: html, range: NSRange(location: 0, length: ns.length))
        var items: [RemoteItem] = []

        for m in matches {
            guard m.numberOfRanges >= 2 else { continue }
            let href = ns.substring(with: m.range(at: 1))
            if href.hasPrefix("?") || href.hasPrefix("#") { continue }
            if href == "../" { continue }

            let decoded = href.removingPercentEncoding ?? href
            if decoded.hasSuffix("/") { continue } // keep flat list for simplicity

            let ext = (decoded as NSString).pathExtension.lowercased()
            guard ["png", "jpg", "jpeg", "pdf", "heic", "heif", "tif", "tiff"].contains(ext) else { continue }

            if let url = URL(string: href, relativeTo: baseURL)?.absoluteURL {
                items.append(.init(url: url, display: url.lastPathComponent))
            }
        }

        return Array(Set(items)).sorted { $0.display.lowercased() < $1.display.lowercased() }
    }
#endif
}

enum OCR {
    static func recognizeText(from images: [CGImage]) async throws -> String {
        var all: [String] = []
        let ctx = CIContext(options: [
            .useSoftwareRenderer: false,
        ])

        for image in images {
            let processed = preprocess(image, context: ctx, scale: 1.5, contrast: 1.35, brightness: 0.02, sharpness: 0.55) ?? image
            let primary = try recognizeLines(cgImage: processed, minimumTextHeight: 0.01, usesLanguageCorrection: true)

            var combined = primary

            // If we didn't catch a ZIP in the full-frame pass, do a targeted crop pass
            // (Texas DL often has City/ST/ZIP as small text under the street line).
            if !containsZipOrCityStateZip(combined) {
                let crops = cropCandidatesForAddressRegion(processed)
                for crop in crops {
                    // Stronger preprocessing for tiny address text.
                    let enhanced = preprocessBinarized(crop, context: ctx, scale: 3.0) ?? crop
                    let secondary = try recognizeLines(cgImage: enhanced, minimumTextHeight: 0.005, usesLanguageCorrection: false)
                    if !secondary.isEmpty {
                        combined += "\n" + secondary
                        if containsZipOrCityStateZip(combined) {
                            break
                        }
                    }
                }
            }

            all.append(combined.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return all.joined(separator: "\n\n")
    }

    private static func recognizeLines(cgImage: CGImage, minimumTextHeight: Float, usesLanguageCorrection: Bool) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = usesLanguageCorrection
        request.recognitionLanguages = ["en-US"]
        // Encourage recognition of smaller text.
        request.minimumTextHeight = minimumTextHeight

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        // Keep more candidates to reduce "missed" small text like City/ZIP.
        // We'll dedupe per line to avoid too much noise.
        let lines = (request.results ?? [])
            .compactMap { obs -> String? in
                let cands = obs.topCandidates(3).map { $0.string.trimmingCharacters(in: .whitespacesAndNewlines) }
                let uniq = Array(NSOrderedSet(array: cands)) as? [String] ?? cands
                return uniq.first(where: { !$0.isEmpty })
            }

        return lines.joined(separator: "\n")
    }

    private static func preprocess(
        _ image: CGImage,
        context: CIContext,
        scale: CGFloat,
        contrast: CGFloat,
        brightness: CGFloat,
        sharpness: CGFloat
    ) -> CGImage? {
        // OCR often misses small/light text. Boost contrast, desaturate, and sharpen a bit.
        let ci = CIImage(cgImage: image)

        let color = CIFilter.colorControls()
        color.inputImage = ci
        color.saturation = 0.0
        color.contrast = Float(contrast)
        color.brightness = Float(brightness)

        let sharpen = CIFilter.sharpenLuminance()
        sharpen.inputImage = color.outputImage
        sharpen.sharpness = Float(sharpness)

        // Upscale slightly to help small fonts (city/zip lines).
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        let out = (sharpen.outputImage ?? color.outputImage ?? ci).transformed(by: transform)

        return context.createCGImage(out, from: out.extent)
    }

    private static func preprocessBinarized(_ image: CGImage, context: CIContext, scale: CGFloat) -> CGImage? {
        // More aggressive preprocessing to pull out tiny high-frequency text.
        let ci = CIImage(cgImage: image)

        let color = CIFilter.colorControls()
        color.inputImage = ci
        color.saturation = 0.0
        color.contrast = 1.95
        color.brightness = 0.06

        // Slight gamma curve by scaling RGB to increase midtones.
        let matrix = CIFilter.colorMatrix()
        matrix.inputImage = color.outputImage
        matrix.rVector = CIVector(x: 1.15, y: 0, z: 0, w: 0)
        matrix.gVector = CIVector(x: 0, y: 1.15, z: 0, w: 0)
        matrix.bVector = CIVector(x: 0, y: 0, z: 1.15, w: 0)
        matrix.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)

        let sharpen = CIFilter.sharpenLuminance()
        sharpen.inputImage = matrix.outputImage ?? color.outputImage
        sharpen.sharpness = 1.0

        let out = (sharpen.outputImage ?? matrix.outputImage ?? color.outputImage ?? ci)
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return context.createCGImage(out, from: out.extent)
    }

    private static func containsZipOrCityStateZip(_ text: String) -> Bool {
        let upper = text.uppercased()
        if upper.range(of: #"\b\d{5}\b"#, options: .regularExpression) != nil { return true }
        if upper.range(of: #"\b[A-Z]{2}\s*\d{5}\b"#, options: .regularExpression) != nil { return true }
        if upper.range(of: #"\b[A-Z]{3,}\s+TX\s+\d{5}\b"#, options: .regularExpression) != nil { return true }
        return false
    }

    private static func cropCandidatesForAddressRegion(_ image: CGImage) -> [CGImage] {
        // Empirical crops (front of TX DL): address block is left-middle and left-lower.
        let w = CGFloat(image.width)
        let h = CGFloat(image.height)
        if w <= 2 || h <= 2 { return [] }

        let rects: [CGRect] = [
            // mid-left band (street + city line)
            CGRect(x: 0, y: h * 0.30, width: w * 0.68, height: h * 0.40),
            // slightly lower (city/state/zip line tends to be lower)
            CGRect(x: 0, y: h * 0.42, width: w * 0.70, height: h * 0.36),
            // tighter crop just under street line
            CGRect(x: 0, y: h * 0.46, width: w * 0.62, height: h * 0.22),
        ].map { $0.integral }

        var out: [CGImage] = []
        for r in rects {
            if let c = image.cropping(to: r) {
                out.append(c)
            }
        }
        return out
    }
}

enum Barcode {
    static func detectPayloads(in images: [CGImage]) throws -> [String] {
        var all: [String] = []
        for img in images {
            all.append(contentsOf: try detectPayloads(in: img))
            if let enhanced = enhanceForBarcode(img) {
                all.append(contentsOf: try detectPayloads(in: enhanced))
            }
        }
        // Dedupe but keep stable-ish order.
        var seen = Set<String>()
        var out: [String] = []
        for p in all {
            let t = p.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { continue }
            if seen.insert(t).inserted {
                out.append(t)
            }
        }
        return out
    }

    static func detectPayloads(in image: CGImage) throws -> [String] {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [
            .pdf417,
            .qr,
            .aztec,
            .code128,
            .dataMatrix,
        ]

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        let payloads = (request.results ?? [])
            .compactMap { $0.payloadStringValue }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return payloads
    }

    private static func enhanceForBarcode(_ image: CGImage) -> CGImage? {
        // Upscale and increase contrast to help PDF417 detection on blurry/compressed imports.
        let ci = CIImage(cgImage: image)
        let ctx = CIContext(options: [
            .useSoftwareRenderer: false,
        ])

        let color = CIFilter.colorControls()
        color.inputImage = ci
        color.saturation = 0.0
        color.contrast = 1.6
        color.brightness = 0.02

        let scale: CGFloat = 1.8
        let out = (color.outputImage ?? ci).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return ctx.createCGImage(out, from: out.extent)
    }
}

enum DriverLicenseParser {
    // Heuristic-only parsing. This stays on device; no network calls.
    static func parse(_ text: String) -> DriverLicenseScanResult {
        let normalized = text
            .replacingOccurrences(of: "\r", with: "\n")
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let joined = normalized.joined(separator: "\n")

        var result = DriverLicenseScanResult(rawText: joined)

        // DOB heuristics: prefer explicit DOB/Birth lines first (otherwise we might pick issue/expiry).
        result.dateOfBirth = nil

        // Issue / expiry heuristics (OCR only): look for lines containing "ISS" or "EXP".
        if let issueLine = normalized.first(where: { $0.lowercased().contains("iss") || $0.lowercased().contains("issued") }),
           let d = firstDate(in: issueLine) {
            result.issueDate = d
        }
        if let expLine = normalized.first(where: { $0.lowercased().contains("exp") || $0.lowercased().contains("expires") || $0.lowercased().contains("expiration") }),
           let d = firstDate(in: expLine) {
            result.expiryDate = d
        }

        // Look for "DOB" / "Birth" lines.
        if let dobLine = normalized.first(where: {
            let l = $0.lowercased()
            return l.contains("dob") || l.contains("birth") || l.contains("date of birth")
        }),
        let d = firstDate(in: dobLine) {
            result.dateOfBirth = d
        } else {
            // Fallback: any date in the document.
            result.dateOfBirth = firstDate(in: joined)
        }

        // Name heuristics:
        // - Prefer explicit "Name:" lines, but avoid "Driver License" / "License" header lines.
        if let nameLine = normalized.first(where: {
            let l = $0.lowercased()
            return l.hasPrefix("name") && !l.contains("license")
        }) {
            let cleaned = nameLine
                .replacingOccurrences(of: "Name", with: "", options: [.caseInsensitive])
                .replacingOccurrences(of: ":", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty {
                result.fullName = cleaned
            }
        }

        if result.fullName == nil {
            // Fallback: pick the first line that looks like a person name (letters/spaces, 2+ words)
            // but exclude common non-name headers.
            result.fullName = normalized.first(where: looksLikeName)
        }

        if let full = result.fullName {
            let split = splitName(full)
            result.firstName = split.first
            result.lastName = split.last
        }

        // Address heuristics: find a line containing a street number.
        if let addrIdx = normalized.firstIndex(where: looksLikeStreetAddress) {
            result.addressLine1 = normalized[addrIdx]

            // Try city/state/zip on next line or same line
            let next = addrIdx + 1 < normalized.count ? normalized[addrIdx + 1] : nil
            if let next, let csz = parseCityStateZip(next) {
                result.city = csz.city
                result.state = csz.state
                result.postalCode = csz.zip
            } else if let csz = parseCityStateZip(normalized[addrIdx]) {
                result.city = csz.city
                result.state = csz.state
                result.postalCode = csz.zip
            }
        } else {
            // Try to parse any city/state/zip line
            if let line = normalized.first(where: { parseCityStateZip($0) != nil }), let csz = parseCityStateZip(line) {
                result.city = csz.city
                result.state = csz.state
                result.postalCode = csz.zip
            }
        }

        return result
    }

    static func merge(primary: DriverLicenseScanResult, fallback: DriverLicenseScanResult) -> DriverLicenseScanResult {
        var out = primary
        if out.fullName == nil { out.fullName = fallback.fullName }
        if out.firstName == nil { out.firstName = fallback.firstName }
        if out.lastName == nil { out.lastName = fallback.lastName }
        if out.dateOfBirth == nil { out.dateOfBirth = fallback.dateOfBirth }
        if out.documentNumber == nil { out.documentNumber = fallback.documentNumber }
        if out.issueDate == nil { out.issueDate = fallback.issueDate }
        if out.expiryDate == nil { out.expiryDate = fallback.expiryDate }
        if out.addressLine1 == nil { out.addressLine1 = fallback.addressLine1 }
        if out.city == nil { out.city = fallback.city }
        if out.state == nil { out.state = fallback.state }
        if out.postalCode == nil { out.postalCode = fallback.postalCode }
        if out.genAIValues == nil { out.genAIValues = fallback.genAIValues }
        if out.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            out.rawText = fallback.rawText
        }
        return out
    }

    static func parseAAMVAPDF417(_ payload: String) -> DriverLicenseScanResult? {
        // AAMVA DL/ID PDF417 payload usually contains ANSI header then lines with data element IDs.
        // We parse common fields:
        // DCS last name, DAC first name, DAD middle, DBB DOB (YYYYMMDD), DBA expiry (YYYYMMDD),
        // DBD issue (YYYYMMDD), DAQ document number, DAG address, DAI city, DAJ state, DAK zip.
        let text = payload.replacingOccurrences(of: "\r", with: "\n")
        var lines = text.split(whereSeparator: \.isNewline).map { String($0) }
        if lines.isEmpty {
            lines = text.components(separatedBy: "\n")
        }

        func value(for key: String) -> String? {
            for l in lines {
                if l.hasPrefix(key) {
                    let v = String(l.dropFirst(key.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !v.isEmpty { return v }
                }
            }
            return nil
        }

        let last = value(for: "DCS")
        let first = value(for: "DAC")
        let middle = value(for: "DAD")
        let dobRaw = value(for: "DBB")
        let expRaw = value(for: "DBA")
        let issRaw = value(for: "DBD")
        let docNumber = value(for: "DAQ")
        let addr1 = value(for: "DAG")
        let city = value(for: "DAI")
        let state = value(for: "DAJ")
        let zip = value(for: "DAK")

        if last == nil, first == nil, dobRaw == nil, addr1 == nil, docNumber == nil {
            return nil
        }

        var out = DriverLicenseScanResult(rawText: payload)
        out.firstName = first
        out.lastName = last
        out.documentNumber = docNumber
        if let first, let last {
            out.fullName = [first, middle, last].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " ")
        } else if let last, let first {
            out.fullName = "\(first) \(last)"
        }

        if let dobRaw {
            out.dateOfBirth = parseAAMVADateYYYYMMDD(dobRaw)
        }
        if let issRaw {
            out.issueDate = parseAAMVADateYYYYMMDD(issRaw)
        }
        if let expRaw {
            out.expiryDate = parseAAMVADateYYYYMMDD(expRaw)
        }

        out.addressLine1 = addr1
        out.city = city
        out.state = state
        if let zip {
            out.postalCode = zip.replacingOccurrences(of: "-", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return out
    }

    private static func parseAAMVADateYYYYMMDD(_ s: String) -> Date? {
        let digits = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard digits.count == 8 else { return nil }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyyMMdd"
        return df.date(from: digits)
    }

    private static func splitName(_ fullName: String) -> (first: String?, last: String?) {
        let cleaned = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return (nil, nil) }

        if cleaned.contains(",") {
            // LAST, FIRST MIDDLE
            let parts = cleaned.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            let last = parts.first
            let rest = parts.count > 1 ? parts[1] : ""
            let first = rest.split(separator: " ").first.map(String.init)
            return (first: first, last: last.map { String($0) })
        }

        let parts = cleaned.split(separator: " ")
        guard parts.count >= 2 else { return (first: cleaned, last: nil) }
        let last = String(parts.last!)
        let first = parts.dropLast().joined(separator: " ")
        return (first: String(first), last: last)
    }

    private static func looksLikeName(_ line: String) -> Bool {
        let l = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if l.contains("driver license") || l == "driver license" || l.contains("license") {
            return false
        }
        if l.contains("identification") || l.contains("id card") {
            return false
        }
        let words = line.split(separator: " ")
        guard words.count >= 2 else { return false }
        guard line.range(of: #"^[A-Za-z][A-Za-z\-\.\s]+$"#, options: .regularExpression) != nil else { return false }
        return true
    }

    private static func looksLikeStreetAddress(_ line: String) -> Bool {
        // Simple: starts with digits and has a street-like word.
        guard line.range(of: #"^\d+\s+\S+"#, options: .regularExpression) != nil else { return false }
        return true
    }

    private static func firstDate(in s: String) -> Date? {
        let patterns = [
            #"(\d{1,2})/(\d{1,2})/(\d{4})"#,
            #"(\d{1,2})-(\d{1,2})-(\d{4})"#,
            #"(\d{4})-(\d{1,2})-(\d{1,2})"#,
        ]
        for p in patterns {
            if let match = s.range(of: p, options: .regularExpression) {
                let str = String(s[match])
                if let d = parseDate(str) { return d }
            }
        }
        return nil
    }

    private static func parseDate(_ str: String) -> Date? {
        let fmts = ["MM/dd/yyyy", "M/d/yyyy", "MM-d-yyyy", "M-d-yyyy", "yyyy-MM-dd", "yyyy-M-d"]
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        for f in fmts {
            df.dateFormat = f
            if let d = df.date(from: str) { return d }
        }
        return nil
    }

    private struct CityStateZip { let city: String; let state: String; let zip: String }

    private static func parseCityStateZip(_ line: String) -> CityStateZip? {
        // Example: Austin, TX 78701
        // Example: Austin TX 78701
        let cleaned = line.replacingOccurrences(of: ",", with: " ")
        let pattern = #"^(.+?)\s+([A-Z]{2})\s+(\d{5})(?:-\d{4})?$"#
        guard let r = cleaned.range(of: pattern, options: .regularExpression) else { return nil }
        let match = String(cleaned[r])
        // Split by spaces from end
        let parts = match.split(separator: " ")
        guard parts.count >= 3 else { return nil }
        let zip = String(parts.last!)
        let state = String(parts[parts.count - 2])
        let city = parts.dropLast(2).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return CityStateZip(city: city, state: state, zip: zip)
    }

    static let demoDriverLicenseText = """
    DRIVER LICENSE
    Name: DOE, JANE
    DOB 04/25/1990
    2457 MEADOWBROOK AVE
    AUSTIN TX 78701
    """
}
