import CoreImage
import Vision

/// Image preprocessing before OCR — Vision primary path; hooks for deskew/HDR when CoreML layout models ship.
enum ImagePreprocessor {
    struct Result {
        let image: CGImage
        let appliedPasses: [String]
    }

    static func prepareForOCR(_ image: CGImage) -> Result {
        var passes: [String] = ["contrast_enhance"]
        var working = image

        if let corrected = applyContrastEnhancement(working) {
            working = corrected
            passes.append("adaptive_contrast")
        }

        if let orientation = detectOrientationHint(for: working) {
            passes.append("orientation_\(orientation)")
        }

        return Result(image: working, appliedPasses: passes)
    }

    private static func applyContrastEnhancement(_ image: CGImage) -> CGImage? {
        let ci = CIImage(cgImage: image)
        let filter = CIFilter.colorControls()
        filter.inputImage = ci
        filter.contrast = 1.12
        filter.brightness = 0.02
        filter.saturation = 1.0
        guard let output = filter.outputImage else { return nil }
        let ctx = CIContext(options: [.useSoftwareRenderer: false])
        return ctx.createCGImage(output, from: output.extent)
    }

  private static func detectOrientationHint(for image: CGImage) -> String? {
        let request = VNDetectHorizonRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil,
              let obs = request.results?.first
        else { return nil }
        let angle = obs.angle * 180 / .pi
        if abs(angle) > 2 { return "deskew_pending_\(Int(angle))" }
        return nil
    }
}
