#!/usr/bin/env swift

import AppKit

struct IconSpec {
  let size: Int
  let filename: String
}

let appName = "Dream Work Reality"
let monogram = "DWR"

let specs: [IconSpec] = [
  .init(size: 20, filename: "AppIcon-20.png"),
  .init(size: 29, filename: "AppIcon-29.png"),
  .init(size: 40, filename: "AppIcon-40.png"),
  .init(size: 58, filename: "AppIcon-58.png"),
  .init(size: 60, filename: "AppIcon-60.png"),
  .init(size: 76, filename: "AppIcon-76.png"),
  .init(size: 80, filename: "AppIcon-80.png"),
  .init(size: 87, filename: "AppIcon-87.png"),
  .init(size: 120, filename: "AppIcon-120.png"),
  .init(size: 152, filename: "AppIcon-152.png"),
  .init(size: 167, filename: "AppIcon-167.png"),
  .init(size: 180, filename: "AppIcon-180.png"),
  .init(size: 1024, filename: "AppIcon-1024.png"),
]

func makeSyntheticIcon(size: Int) -> NSImage {
  let img = NSImage(size: NSSize(width: size, height: size))
  img.lockFocusFlipped(false)
  defer { img.unlockFocus() }

  let ctx = NSGraphicsContext.current!.cgContext
  ctx.setAllowsAntialiasing(true)
  ctx.setShouldAntialias(true)
  ctx.interpolationQuality = .high

  // Background gradient (midnight indigo -> near-black)
  let bgPath = NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size))
  let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.10, green: 0.12, blue: 0.30, alpha: 1.0),
    NSColor(calibratedRed: 0.03, green: 0.03, blue: 0.08, alpha: 1.0),
  ])!
  gradient.draw(in: bgPath, angle: 270)

  // Subtle vignette.
  ctx.saveGState()
  ctx.setFillColor(NSColor(calibratedWhite: 0, alpha: 0.20).cgColor)
  ctx.fillEllipse(in: CGRect(x: -CGFloat(size) * 0.15,
                             y: -CGFloat(size) * 0.10,
                             width: CGFloat(size) * 1.3,
                             height: CGFloat(size) * 1.2))
  ctx.restoreGState()

  // Emblem: crescent + sun arc (simple, scalable vector)
  let accent = NSColor(calibratedRed: 0.35, green: 0.90, blue: 0.86, alpha: 1.0)
  ctx.saveGState()
  ctx.setStrokeColor(accent.cgColor)
  ctx.setLineWidth(CGFloat(size) * 0.035)
  ctx.setLineCap(.round)

  let center = CGPoint(x: CGFloat(size) * 0.5, y: CGFloat(size) * 0.62)
  let rOuter = CGFloat(size) * 0.16
  let rInner = CGFloat(size) * 0.12

  // Crescent: outer arc
  ctx.addArc(center: center, radius: rOuter, startAngle: .pi * 0.10, endAngle: .pi * 1.55, clockwise: false)
  ctx.strokePath()
  // Crescent: inner arc (offset to create crescent feel)
  let innerCenter = CGPoint(x: center.x + CGFloat(size) * 0.035, y: center.y + CGFloat(size) * 0.010)
  ctx.addArc(center: innerCenter, radius: rInner, startAngle: .pi * 0.10, endAngle: .pi * 1.55, clockwise: false)
  ctx.strokePath()

  // Sun arc (rising)
  let sunCenter = CGPoint(x: CGFloat(size) * 0.5, y: CGFloat(size) * 0.58)
  let sunR = CGFloat(size) * 0.18
  ctx.addArc(center: sunCenter, radius: sunR, startAngle: .pi * 1.10, endAngle: .pi * 1.90, clockwise: false)
  ctx.strokePath()

  // Horizon line
  ctx.move(to: CGPoint(x: CGFloat(size) * 0.30, y: CGFloat(size) * 0.48))
  ctx.addLine(to: CGPoint(x: CGFloat(size) * 0.70, y: CGFloat(size) * 0.48))
  ctx.strokePath()

  // Accent glow
  ctx.setShadow(offset: .zero, blur: CGFloat(size) * 0.035, color: accent.withAlphaComponent(0.35).cgColor)
  ctx.move(to: CGPoint(x: CGFloat(size) * 0.30, y: CGFloat(size) * 0.48))
  ctx.addLine(to: CGPoint(x: CGFloat(size) * 0.70, y: CGFloat(size) * 0.48))
  ctx.strokePath()
  ctx.restoreGState()

  // Monogram
  let monoFont = NSFont.systemFont(ofSize: CGFloat(size) * 0.22, weight: .semibold)
  let monoAttrs: [NSAttributedString.Key: Any] = [
    .font: monoFont,
    .foregroundColor: NSColor.white.withAlphaComponent(0.92),
    .kern: CGFloat(size) * 0.020,
  ]
  let monoStr = NSAttributedString(string: monogram, attributes: monoAttrs)
  let monoSize = monoStr.size()
  let monoRect = NSRect(
    x: (CGFloat(size) - monoSize.width) * 0.5,
    y: CGFloat(size) * 0.30,
    width: monoSize.width,
    height: monoSize.height
  )
  monoStr.draw(in: monoRect)

  // Small stacked title
  let labelFont = NSFont.systemFont(ofSize: CGFloat(size) * 0.060, weight: .medium)
  let para = NSMutableParagraphStyle()
  para.alignment = .center

  let labelAttrs: [NSAttributedString.Key: Any] = [
    .font: labelFont,
    .foregroundColor: NSColor.white.withAlphaComponent(0.70),
    .kern: CGFloat(size) * 0.010,
    .paragraphStyle: para,
  ]

  let lines = ["DREAM", "WORK", "REALITY"]
  let lineHeight = labelFont.ascender - labelFont.descender
  let totalHeight = lineHeight * CGFloat(lines.count) + CGFloat(size) * 0.010 * CGFloat(lines.count - 1)
  var y = CGFloat(size) * 0.18 + totalHeight
  for line in lines {
    let s = NSAttributedString(string: line, attributes: labelAttrs)
    y -= lineHeight
    s.draw(in: NSRect(x: 0, y: y, width: CGFloat(size), height: lineHeight))
    y -= CGFloat(size) * 0.010
  }

  // Ensure we never exceed icon safe margins visually.
  _ = appName // Keep for future customization.
  return img
}

func loadImage(at path: String) throws -> NSImage {
  let url = URL(fileURLWithPath: path)
  guard let img = NSImage(contentsOf: url) else {
    throw NSError(domain: "icon-gen", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to load image at \(path)"])
  }
  return img
}

func makeIconFromSource(_ source: NSImage, size: Int) throws -> NSImage {
  // Render a square icon by aspect-fill scaling and center-cropping the source.
  let targetSize = NSSize(width: size, height: size)
  let out = NSImage(size: targetSize)
  out.lockFocusFlipped(false)
  defer { out.unlockFocus() }

  let ctx = NSGraphicsContext.current!.cgContext
  ctx.setAllowsAntialiasing(true)
  ctx.setShouldAntialias(true)
  ctx.interpolationQuality = .high

  var srcRect = NSRect(origin: .zero, size: source.size)
  // Some NSImages report 0 size until they are rasterized; fall back to a common dimension.
  if srcRect.width <= 0 || srcRect.height <= 0 {
    if let rep = source.representations.first {
      srcRect.size = NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
    }
  }
  guard srcRect.width > 0, srcRect.height > 0 else {
    throw NSError(domain: "icon-gen", code: 3, userInfo: [NSLocalizedDescriptionKey: "Source image has invalid size"])
  }

  let scale = max(CGFloat(size) / srcRect.width, CGFloat(size) / srcRect.height)
  let drawW = srcRect.width * scale
  let drawH = srcRect.height * scale
  let drawRect = NSRect(
    x: (CGFloat(size) - drawW) * 0.5,
    y: (CGFloat(size) - drawH) * 0.5,
    width: drawW,
    height: drawH
  )

  source.draw(in: drawRect,
              from: srcRect,
              operation: .sourceOver,
              fraction: 1.0,
              respectFlipped: false,
              hints: [.interpolation: NSImageInterpolation.high])

  return out
}

func writePNG(image: NSImage, to url: URL) throws {
  guard let tiff = image.tiffRepresentation,
        let rep = NSBitmapImageRep(data: tiff),
        let png = rep.representation(using: .png, properties: [.compressionFactor: 1.0]) else {
    throw NSError(domain: "icon-gen", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to render PNG"])
  }
  try png.write(to: url, options: .atomic)
}

func main() throws {
  let args = CommandLine.arguments
  let outDir: URL
  if let idx = args.firstIndex(of: "--out"), idx + 1 < args.count {
    outDir = URL(fileURLWithPath: args[idx + 1], isDirectory: true)
  } else {
    outDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
  }

  let inPath: String?
  if let idx = args.firstIndex(of: "--in"), idx + 1 < args.count {
    inPath = args[idx + 1]
  } else {
    inPath = nil
  }

  try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

  let sourceImage: NSImage? = try inPath.map { try loadImage(at: $0) }

  for spec in specs {
    let img: NSImage
    if let sourceImage {
      img = try makeIconFromSource(sourceImage, size: spec.size)
    } else {
      img = makeSyntheticIcon(size: spec.size)
    }
    let url = outDir.appendingPathComponent(spec.filename)
    try writePNG(image: img, to: url)
  }

  fputs("Generated \(specs.count) icons in \(outDir.path)\n", stderr)
}

do {
  try main()
} catch {
  fputs("Icon generation failed: \(error)\n", stderr)
  exit(1)
}

