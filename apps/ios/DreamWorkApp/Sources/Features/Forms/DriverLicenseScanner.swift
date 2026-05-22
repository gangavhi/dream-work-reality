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
    var middleName: String?
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
enum DriverLicenseScannerPipeline {
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

        // Build profile: OCR + GenAI fill gaps; barcode wins for authoritative ID fields.
        var merged = ocrParsed
        if let genAIParsed {
            merged = DriverLicenseParser.merge(primary: genAIParsed, fallback: merged)
        }
        if let barcodeParsed {
            merged = DriverLicenseParser.merge(primary: barcodeParsed, fallback: merged)
        }
        if !ScanFieldValidator.isPlausiblePersonName(merged.fullName ?? "") {
            merged.fullName = barcodeParsed?.fullName ?? (ScanFieldValidator.isPlausiblePersonName(ocrParsed.fullName ?? "") ? ocrParsed.fullName : nil)
            if let full = merged.fullName {
                let split = DriverLicenseParser.splitNameForMerge(full)
                merged.firstName = split.first
                merged.lastName = split.last
            }
        }
        if let display = DriverLicenseFormatting.displayName(
            first: merged.firstName,
            middle: merged.middleName,
            last: merged.lastName
        ), ScanFieldValidator.isPlausiblePersonName(display) {
            merged.fullName = display
        }

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
        guard let uiImage = UIImage(data: data),
              let cg = uiImage.normalizedCGImage() ?? makeCGImage(from: uiImage)
        else {
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
        let scale: CGFloat = 3.0
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
        if let mapped = await GenAIFieldMapper.mapDriverLicense(from: rawText) {
            return mapped
        }

        #if DEBUG
        guard ZeroEgressPolicy.isDeveloperCoreAPISyncEnabled else { return nil }
        guard let url = URL(string: "http://127.0.0.1:18081/genai/extract-document"),
              ZeroEgressPolicy.allowsCoreAPILocalhost(url)
        else { return nil }
        let body = ExtractRequest(document_type: "driver_license", raw_text: rawText)
        guard let payload = try? JSONEncoder().encode(body) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = payload
        request.timeoutInterval = 45

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            guard (200..<300).contains(status) else { return nil }
            let decoded = try JSONDecoder().decode(ExtractResponse.self, from: data)
            guard let v = decoded.values, !v.isEmpty else { return nil }
            return GenAIFieldMapper.driverLicenseResult(from: v, rawText: rawText)
        } catch {
            return nil
        }
        #else
        return nil
        #endif
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
    @State private var didAutoPresentPicker = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Scan Document")
                    .font(.title2)

                Text("Import a document to scan (or drag & drop a file from your Mac).")
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
                        Text("Browse Files")
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
            .task {
                // Streamlined UX: auto-open the picker so the user doesn't see an extra
                // "Choose document" step before selecting a file.
                if didAutoPresentPicker { return }
                didAutoPresentPicker = true
#if targetEnvironment(simulator)
                isPresentingDownloadsPicker = true
                await loadSimulatorDownloadsListing()
#else
                isPresentingFilePicker = true
#endif
            }
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
        try await OcrEngine.recognizeText(from: images)
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
        parseInternal(text, includeGenericNames: true)
    }

    /// Used by name resolver — skips generic name heuristics that mis-read Texas LAST/FIRST order.
    static func parseWithoutGenericNames(_ text: String) -> DriverLicenseScanResult {
        parseInternal(text, includeGenericNames: false)
    }

    private static func parseInternal(_ text: String, includeGenericNames: Bool) -> DriverLicenseScanResult {
        let normalized = text
            .replacingOccurrences(of: "\r", with: "\n")
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let joined = normalized.joined(separator: "\n")

        var result = DriverLicenseScanResult(rawText: joined)

        // Issue / expiry heuristics (OCR only): look for lines containing "ISS" or "EXP".
        if let issueLine = normalized.first(where: { $0.lowercased().contains("iss") || $0.lowercased().contains("issued") }),
           let d = firstDate(in: issueLine) {
            result.issueDate = d
        }
        if let expLine = normalized.first(where: { $0.lowercased().contains("exp") || $0.lowercased().contains("expires") || $0.lowercased().contains("expiration") }),
           let d = firstDate(in: expLine) {
            result.expiryDate = d
        }

        // DOB: prefer explicit DOB/Birth labels; never use issue/expiry dates as DOB.
        result.dateOfBirth = extractDateOfBirth(from: normalized, joined: joined, excluding: [result.issueDate, result.expiryDate])

        if includeGenericNames {
            applyGenericNameHeuristics(from: normalized, into: &result)
        }

        if result.documentNumber == nil {
            result.documentNumber = extractDocumentNumber(from: normalized)
        }

        // Address: street line + following city/state/ZIP lines (case-insensitive state).
        let address = extractAddress(from: normalized)
        result.addressLine1 = address.line1
        result.city = address.city
        if let residenceState = address.state {
            result.state = residenceState
        }
        result.postalCode = address.postalCode

        if result.state == nil {
            result.state = extractStateCode(from: normalized)
        }

        // Texas DL numbered fields (1=last, 2=first, 3=DOB, 4a/4b/4d, 8=address) override generic OCR guesses.
        if let texas = TexasDriverLicenseParser.parse(from: normalized, joined: joined) {
            result = merge(primary: texas, fallback: result)
        }

        syncFullNameFromComponents(into: &result)
        return result
    }

    private static func applyGenericNameHeuristics(from normalized: [String], into result: inout DriverLicenseScanResult) {
        for line in normalized {
            if let match = line.range(
                of: #"^([A-Za-z][A-Za-z\-']+)\s*,\s*([A-Za-z][A-Za-z\-'\s]+)$"#,
                options: .regularExpression
            ) {
                let candidate = String(line[match]).trimmingCharacters(in: .whitespacesAndNewlines)
                if ScanFieldValidator.isPlausiblePersonName(candidate) {
                    result.fullName = candidate
                    break
                }
            }
        }

        if result.fullName == nil,
           let nameLine = normalized.first(where: {
               let l = $0.lowercased()
               return (l.hasPrefix("name") || l.hasPrefix("1 ")) && !l.contains("license")
           })
        {
            let cleaned = nameLine
                .replacingOccurrences(of: #"^\d+\s*"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: "Name", with: "", options: [.caseInsensitive])
                .replacingOccurrences(of: ":", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if ScanFieldValidator.isPlausiblePersonName(cleaned) {
                result.fullName = cleaned
            }
        }

        if result.fullName == nil {
            result.fullName = normalized.first(where: looksLikeName)
        }

        if let full = result.fullName {
            let split = splitName(full)
            result.firstName = split.first
            result.lastName = split.last
        }
    }

    private static func syncFullNameFromComponents(into result: inout DriverLicenseScanResult) {
        guard let first = result.firstName?.trimmingCharacters(in: .whitespacesAndNewlines),
              let last = result.lastName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !first.isEmpty, !last.isEmpty,
              ScanFieldValidator.isPlausibleNameComponent(first),
              ScanFieldValidator.isPlausibleNameComponent(last)
        else { return }

        result.fullName = DriverLicenseFormatting.displayName(
            first: first,
            middle: result.middleName,
            last: last
        )
    }

    static func merge(primary: DriverLicenseScanResult, fallback: DriverLicenseScanResult) -> DriverLicenseScanResult {
        var out = primary
        if out.firstName == nil || isGarbageName(out.firstName ?? "") || !ScanFieldValidator.isPlausibleNameComponent(out.firstName ?? "") {
            if let v = fallback.firstName, !isGarbageName(v), ScanFieldValidator.isPlausibleNameComponent(v) {
                out.firstName = v
            }
        }
        if out.lastName == nil || isGarbageName(out.lastName ?? "") || !ScanFieldValidator.isPlausibleNameComponent(out.lastName ?? "") {
            if let v = fallback.lastName, !isGarbageName(v), ScanFieldValidator.isPlausibleNameComponent(v) {
                out.lastName = v
            }
        }
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
        syncFullNameFromComponents(into: &out)
        return out
    }

    private static func isGarbageName(_ value: String) -> Bool {
        let lower = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["none", "eno", "ba.", "ba. eno", "director", "limited", "term", "texas", "texass"].contains(where: { lower.contains($0) })
    }

    static func parseAAMVAPDF417(_ payload: String) -> DriverLicenseScanResult? {
        let text = payload.replacingOccurrences(of: "\r", with: "\n")
        let fields = parseAAMVAFields(in: text)

        func field(_ key: String) -> String? {
            fields[key]?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }

        let last = field("DCS")
        let first = field("DAC")
        let middle = field("DAD")
        let dobRaw = field("DBB")
        let expRaw = field("DBA")
        let issRaw = field("DBD")
        let docNumber = field("DAQ")
        let addr1 = field("DAG")
        let addr2 = field("DAH")
        let city = field("DAI")
        let state = field("DAJ")
        let zip = field("DAK")

        if last == nil, first == nil, dobRaw == nil, addr1 == nil, docNumber == nil {
            return nil
        }

        var out = DriverLicenseScanResult(rawText: payload)
        out.firstName = first
        out.middleName = middle
        out.lastName = last
        out.documentNumber = docNumber
        if let first, let last {
            out.fullName = [first, middle, last]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
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

        out.addressLine1 = [addr1, addr2]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
            .nilIfEmpty ?? addr1
        out.city = city
        out.state = parseAAMVAState(state)
        if let zip {
            let digits = zip.filter(\.isNumber)
            if digits.count >= 5 {
                out.postalCode = String(digits.prefix(9))
            }
        }
        return out
    }

    /// Parses AAMVA PDF417 data element ids (DCS, DBB, DAI, …) from line-based or inline payloads.
    private static func parseAAMVAFields(in text: String) -> [String: String] {
        let knownKeys: Set<String> = [
            "DCS", "DAC", "DAD", "DBB", "DBA", "DBD", "DBE", "DAQ", "DAG", "DAH", "DAI", "DAJ", "DAK",
        ]

        var hits: [(key: String, location: Int)] = []
        let ns = text as NSString
        guard let regex = try? NSRegularExpression(pattern: "[A-Z]{3}") else { return [:] }
        regex.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match else { return }
            let key = ns.substring(with: match.range)
            guard knownKeys.contains(key) else { return }
            hits.append((key, match.range.location))
        }
        hits.sort { $0.location < $1.location }

        var fields: [String: String] = [:]
        for (index, hit) in hits.enumerated() {
            let valueStart = hit.location + 3
            let valueEnd = index + 1 < hits.count ? hits[index + 1].location : ns.length
            guard valueEnd > valueStart else { continue }
            let raw = ns.substring(with: NSRange(location: valueStart, length: valueEnd - valueStart))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { continue }
            // Prefer shorter value when the same key appears more than once (OCR/barcode noise).
            if let existing = fields[hit.key], existing.count <= raw.count {
                continue
            }
            fields[hit.key] = raw
        }
        return fields
    }

    private static func parseAAMVAState(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if trimmed.count == 2, ScanFieldValidator.isPlausibleUSState(trimmed) { return trimmed }
        if trimmed.count > 2 {
            let code = String(trimmed.prefix(2))
            if ScanFieldValidator.isPlausibleUSState(code) { return code }
        }
        return nil
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

    static func splitNameForMerge(_ fullName: String) -> (first: String?, last: String?) {
        splitName(fullName)
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
        ScanFieldValidator.isPlausiblePersonName(line)
    }

    private static func extractDocumentNumber(from lines: [String]) -> String? {
        let patterns = [
            #"(?i)(?:DL|LIC|ID|LICENSE|DOC)\s*#?\s*:?\s*([A-Z0-9\-]{4,20})"#,
            #"(?i)(?:NO|NUM|NUMBER)\.?\s*#?\s*([A-Z0-9\-]{4,20})"#,
            #"(?i)^4d\.?\s*([A-Z0-9\-]{4,20})"#,
        ]
        for line in lines {
            for pattern in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern),
                   let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                   match.numberOfRanges > 1,
                   let range = Range(match.range(at: 1), in: line)
                {
                    let candidate = String(line[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if ScanFieldValidator.isPlausibleDriversLicenseNumber(candidate) {
                        return candidate
                    }
                }
            }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.range(of: #"^[A-Z0-9\-]{5,15}$"#, options: .regularExpression) != nil,
               trimmed.rangeOfCharacter(from: .decimalDigits) != nil,
               ScanFieldValidator.isPlausibleDriversLicenseNumber(trimmed)
            {
                return trimmed
            }
        }
        return nil
    }

    private static func extractStateCode(from lines: [String]) -> String? {
        for line in lines {
            if let csz = parseCityStateZip(line), ScanFieldValidator.isPlausibleUSState(csz.state) {
                return csz.state
            }
        }
        for line in lines {
            let upper = line.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if upper.count == 2, ScanFieldValidator.isPlausibleUSState(upper) {
                return upper
            }
        }
        return nil
    }

    private static func extractDateOfBirth(
        from lines: [String],
        joined: String,
        excluding excluded: [Date?]
    ) -> Date? {
        let excludedSet = Set(excluded.compactMap { $0 })

        func isExcluded(_ date: Date) -> Bool {
            excludedSet.contains { Calendar.current.isDate($0, inSameDayAs: date) }
        }

        // 1) Label on same line: "DOB 04/25/1990", "DOB: 04-25-1990", "3 DOB 04/25/1990"
        for line in lines {
            let lower = line.lowercased()
            guard lower.contains("dob")
                || lower.contains("birth")
                || lower.contains("date of birth")
                || lower.contains("bdate")
            else { continue }

            if let d = firstDate(in: line), !isExcluded(d), isPlausibleBirthDate(d) {
                return d
            }
        }

        // 2) Label on one line, date on the next (common OCR split).
        for (idx, line) in lines.enumerated() {
            let lower = line.lowercased()
            guard lower.contains("dob") || lower.contains("birth") || lower.contains("bdate") else { continue }
            if firstDate(in: line) != nil { continue }
            if idx + 1 < lines.count,
               let d = firstDate(in: lines[idx + 1]),
               !isExcluded(d),
               isPlausibleBirthDate(d)
            {
                return d
            }
        }

        // 3) Any remaining date that isn't issue/expiry and looks like a birth date.
        for d in allDates(in: joined) where !isExcluded(d) && isPlausibleBirthDate(d) {
            return d
        }
        return nil
    }

    private static func isPlausibleBirthDate(_ date: Date) -> Bool {
        let now = Date()
        guard date <= now else { return false }
        let years = Calendar.current.dateComponents([.year], from: date, to: now).year ?? 0
        return years >= 14 && years <= 110
    }

    private static func allDates(in text: String) -> [Date] {
        let patterns = [
            #"(\d{1,2}/\d{1,2}/\d{4})"#,
            #"(\d{1,2}-\d{1,2}-\d{4})"#,
            #"(\d{4}-\d{1,2}-\d{1,2})"#,
            #"(\d{1,2}/\d{1,2}/\d{2})"#,
        ]
        var found: [Date] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            regex.enumerateMatches(in: text, range: range) { match, _, _ in
                guard let match, match.numberOfRanges > 1, let r = Range(match.range(at: 1), in: text) else { return }
                if let d = parseDate(String(text[r])) {
                    found.append(d)
                }
            }
        }
        return found
    }

    private struct ParsedAddress {
        var line1: String?
        var city: String?
        var state: String?
        var postalCode: String?
    }

    private static func extractAddress(from lines: [String]) -> ParsedAddress {
        var result = ParsedAddress()

        // Full single-line address: "123 Main St, Austin, TX 78701"
        for line in lines {
            if let combined = parseFullAddressLine(line) {
                return combined
            }
        }

        guard let addrIdx = lines.firstIndex(where: looksLikeStreetAddress) else {
            if let line = lines.first(where: { parseCityStateZip($0) != nil }),
               let csz = parseCityStateZip(line)
            {
                result.city = csz.city
                result.state = csz.state
                result.postalCode = csz.zip
            }
            return result
        }

        result.line1 = cleanStreetLine(lines[addrIdx])

        // City/state/ZIP often on the next 1–2 lines; skip apt/unit lines when hunting CSZ.
        for offset in 1 ... 3 {
            let idx = addrIdx + offset
            guard idx < lines.count else { break }
            let candidate = lines[idx]
            if looksLikeStreetAddress(candidate), result.line1?.contains(candidate) != true {
                // Apt / suite line — append to street address.
                let extra = cleanStreetLine(candidate)
                if let existing = result.line1, !existing.isEmpty {
                    result.line1 = "\(existing), \(extra)"
                } else {
                    result.line1 = extra
                }
                continue
            }
            if let csz = parseCityStateZip(candidate) {
                result.city = csz.city
                result.state = csz.state
                result.postalCode = csz.zip
                break
            }
        }

        if result.city == nil, let csz = parseCityStateZip(lines[addrIdx]) {
            result.city = csz.city
            result.state = csz.state
            result.postalCode = csz.zip
            if let street = csz.street {
                result.line1 = street
            }
        }

        return result
    }

    private static func parseFullAddressLine(_ line: String) -> ParsedAddress? {
        // 123 Main St, Austin, TX 78701
        let pattern = #"(?i)^(\d[\w\s\.\#\-]+?),\s*(.+?),\s*([A-Z]{2})\s+(\d{5}(?:-\d{4})?)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              match.numberOfRanges >= 5,
              let r1 = Range(match.range(at: 1), in: line),
              let r2 = Range(match.range(at: 2), in: line),
              let r3 = Range(match.range(at: 3), in: line),
              let r4 = Range(match.range(at: 4), in: line)
        else { return nil }

        return ParsedAddress(
            line1: cleanStreetLine(String(line[r1])),
            city: String(line[r2]).trimmingCharacters(in: .whitespacesAndNewlines),
            state: String(line[r3]).uppercased(),
            postalCode: String(line[r4])
        )
    }

    private static func cleanStreetLine(_ line: String) -> String {
        line
            .replacingOccurrences(
                of: #"^(?i)(?:address|addr|residence|res)\s*:?\s*"#,
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func looksLikeStreetAddress(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.range(of: #"^\d+\s+\S+"#, options: .regularExpression) != nil else { return false }
        let lower = trimmed.lowercased()
        if lower.contains("dob") || lower.contains("exp") || lower.contains("iss") { return false }
        return true
    }

    private static func firstDate(in s: String) -> Date? {
        let patterns = [
            #"(\d{1,2}/\d{1,2}/\d{4})"#,
            #"(\d{1,2})-(\d{1,2})-(\d{4})"#,
            #"(\d{4})-(\d{1,2})-(\d{1,2})"#,
            #"(\d{1,2}/\d{1,2}/\d{2})"#,
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
        let fmts = ["MM/dd/yyyy", "M/d/yyyy", "MM-d-yyyy", "M-d-yyyy", "yyyy-MM-dd", "yyyy-M-d", "MM/dd/yy", "M/d/yy"]
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        for f in fmts {
            df.dateFormat = f
            if let d = df.date(from: str) {
                if f.contains("yy"), !f.contains("yyyy") {
                    // Expand 2-digit year: 90 -> 1990, 05 -> 2005
                    let year = Calendar.current.component(.year, from: d)
                    if year > Calendar.current.component(.year, from: Date()) {
                        return Calendar.current.date(byAdding: .year, value: -100, to: d) ?? d
                    }
                }
                return d
            }
        }
        return nil
    }

    private struct CityStateZip {
        let city: String
        let state: String
        let zip: String
        let street: String?
    }

    private static func parseCityStateZip(_ line: String) -> CityStateZip? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        // Combined: "123 Main St Austin TX 78701" — extract trailing CSZ.
        let trailingPattern = #"(?i)^(.+?)\s+([A-Za-z]{2})\s+(\d{5}(?:-\d{4})?)$"#
        if let regex = try? NSRegularExpression(pattern: trailingPattern),
           let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
           match.numberOfRanges >= 4,
           let cityRange = Range(match.range(at: 1), in: trimmed),
           let stateRange = Range(match.range(at: 2), in: trimmed),
           let zipRange = Range(match.range(at: 3), in: trimmed)
        {
            let cityPart = String(trimmed[cityRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let state = String(trimmed[stateRange]).uppercased()
            let zip = String(trimmed[zipRange])
            guard ScanFieldValidator.isPlausibleUSState(state) else { return nil }

            // Split leading street from city when glued on one line.
            if let streetMatch = cityPart.range(of: #"(?i)^(\d+\s+.+?)\s+([A-Za-z][A-Za-z\s'\-\.]+)$"#, options: .regularExpression) {
                let parts = cityPart[streetMatch]
                if let inner = try? NSRegularExpression(pattern: #"(?i)^(\d+\s+.+?)\s+([A-Za-z][A-Za-z\s'\-\.]+)$"#),
                   let m = inner.firstMatch(in: String(parts), range: NSRange(parts.startIndex..., in: parts)),
                   m.numberOfRanges >= 3,
                   let sRange = Range(m.range(at: 1), in: parts),
                   let cRange = Range(m.range(at: 2), in: parts)
                {
                    return CityStateZip(
                        city: String(parts[cRange]).trimmingCharacters(in: .whitespacesAndNewlines),
                        state: state,
                        zip: zip,
                        street: cleanStreetLine(String(parts[sRange]))
                    )
                }
            }

            return CityStateZip(city: cityPart, state: state, zip: zip, street: nil)
        }

        // Standard: "Austin, TX 78701" or "Austin TX 78701"
        let cleaned = trimmed.replacingOccurrences(of: ",", with: " ")
        let pattern = #"(?i)^(.+?)\s+([A-Za-z]{2})\s+(\d{5})(?:-(\d{4}))?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)),
              match.numberOfRanges >= 4,
              let cityRange = Range(match.range(at: 1), in: cleaned),
              let stateRange = Range(match.range(at: 2), in: cleaned),
              let zipRange = Range(match.range(at: 3), in: cleaned)
        else { return nil }

        let state = String(cleaned[stateRange]).uppercased()
        guard ScanFieldValidator.isPlausibleUSState(state) else { return nil }
        let city = String(cleaned[cityRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        let zip = String(cleaned[zipRange])
        return CityStateZip(city: city, state: state, zip: zip, street: nil)
    }

    static let demoDriverLicenseText = """
    DRIVER LICENSE
    Name: DOE, JANE
    DOB 04/25/1990
    2457 MEADOWBROOK AVE
    AUSTIN TX 78701
    """
}

// MARK: - Scan entry screen (exposes scanner in the main tab bar)

@MainActor
struct ScanView: View {
    @EnvironmentObject private var appState: AppState

    @State private var isPresentingScanner = false
    @State private var banner: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Scan Document")
                    .font(.title2)

                Text("Choose a driver license (camera on device, or Mac Downloads on Simulator) and we’ll save/update the profile automatically.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button {
                    isPresentingScanner = true
                } label: {
                    HStack {
                        Text("Choose Document")
                        Spacer()
                        Image(systemName: "doc")
                    }
                }
                .buttonStyle(.borderedProminent)

                if let banner {
                    Text(banner)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Scan")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $isPresentingScanner) {
            DriverLicenseScannerView { result in
                switch result {
                case .success(let scan):
                    let profile = buildProfile(from: scan)
                    let record = personRecord(from: profile)
                    if appState.savePerson(record) {
                        banner = "Saved profile: \(profile.displayTitle)"
                        appState.openPeople()
                    } else {
                        banner = "Scan succeeded but saving the profile failed."
                    }
                case .failure(let err):
                    banner = "Scan failed: \(err.localizedDescription)"
                }
                isPresentingScanner = false
            }
            .ignoresSafeArea()
        }
    }

    private func buildProfile(from scan: DriverLicenseScanResult) -> PersonProfile {
        let fn = scan.firstName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let ln = scan.lastName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let full = scan.fullName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let nickname = ([fn, ln].filter { !$0.isEmpty }.joined(separator: " ").nilIfEmpty) ?? (full.nilIfEmpty ?? "New Profile")

        var p = PersonProfile(nickname: nickname)
        p.firstName = fn.nilIfEmpty
        p.lastName = ln.nilIfEmpty
        if let dob = scan.dateOfBirth {
            p.dateOfBirthMMDDYYYY = formatMMDDYYYY(dob)
        }

        // Address
        p.addressLine1 = scan.addressLine1?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        p.city = scan.city?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        p.state = scan.state?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        p.postalCode = scan.postalCode?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty

        // Active DL + DL history (always override from scan).
        let dl = DriverLicense(
            number: scan.documentNumber?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            state: scan.state?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            issueMMDDYYYY: scan.issueDate.map(formatMMDDYYYY),
            expiryMMDDYYYY: scan.expiryDate.map(formatMMDDYYYY),
            isActive: true,
            capturedAt: Date()
        )
        p.driverLicenses = [dl]
        p.driverLicenseNumber = dl.number
        p.driverLicenseIssueMMDDYYYY = dl.issueMMDDYYYY
        p.driverLicenseExpiryMMDDYYYY = dl.expiryMMDDYYYY
        p.driverLicenseState = dl.state
        p.documents = [
            ScannedDocument(
                type: "driver_license",
                number: dl.number,
                issueMMDDYYYY: dl.issueMMDDYYYY,
                expiryMMDDYYYY: dl.expiryMMDDYYYY,
                rawText: scan.rawText,
                capturedAt: dl.capturedAt
            ),
        ]
        if let all = scan.genAIValues {
            p.genAIFields = all
        }

        p.updatedAt = Date()
        return p
    }

    private func personRecord(from profile: PersonProfile) -> PersonRecord {
        var record = PersonRecord.empty()
        record = record.withValue(profile.displayTitle, for: ProfileFieldKey.displayName)
        if let value = profile.firstName?.nilIfEmpty {
            record = record.withValue(value, for: ProfileFieldKey.legalFirstName)
        }
        if let value = profile.lastName?.nilIfEmpty {
            record = record.withValue(value, for: ProfileFieldKey.legalLastName)
        }
        if let value = profile.dateOfBirthMMDDYYYY?.nilIfEmpty {
            record = record.withValue(value, for: ProfileFieldKey.dateOfBirth)
        }
        if let value = profile.addressLine1?.nilIfEmpty {
            record = record.withValue(value, for: ProfileFieldKey.addressLine1)
        }
        if let value = profile.city?.nilIfEmpty {
            record = record.withValue(value, for: ProfileFieldKey.city)
        }
        if let value = profile.state?.nilIfEmpty {
            record = record.withValue(value, for: ProfileFieldKey.state)
        }
        if let value = profile.postalCode?.nilIfEmpty {
            record = record.withValue(value, for: ProfileFieldKey.postalCode)
        }
        if let value = profile.driverLicenseNumber?.nilIfEmpty {
            record = record.withValue(value, for: ProfileFieldKey.driversLicenseNumber)
        }
        if let value = profile.driverLicenseState?.nilIfEmpty {
            record = record.withValue(value, for: ProfileFieldKey.driversLicenseState)
        }
        if let value = profile.driverLicenseIssueMMDDYYYY?.nilIfEmpty {
            record = record.withValue(value, for: ProfileFieldKey.driversLicenseIssueDate)
        }
        if let value = profile.driverLicenseExpiryMMDDYYYY?.nilIfEmpty {
            record = record.withValue(value, for: ProfileFieldKey.driversLicenseExpiry)
        }
        for (key, value) in profile.genAIFields where !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            record = record.withValue(value, for: key)
        }
        return record
    }

    private func formatMMDDYYYY(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "MM/dd/yyyy"
        return df.string(from: date)
    }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
