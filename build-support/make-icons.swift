// Generates Stripe's icons from one definition of the mark: "STR" standing on a
// thick bar (concept D), set in San Francisco Heavy.
//
//   swift build-support/make-icons.swift
//
// Writes:
//   MTMR/Assets.xcassets/StatusImage.imageset/StatusImage.pdf   menu bar + Control Strip
//       (vector, used as a template image, so macOS tints it for light/dark bars)
//   MTMR/Assets.xcassets/AppIcon.appiconset/logo-<size>.png     app icon, white mark on a
//       near-black squircle, drawn separately at each size so small ones stay crisp

import AppKit

// The mark in its own 27×18 space (y down), matching the reviewed design.
enum Mark {
    static let size = CGSize(width: 27, height: 18)

    /// Draws the mark into a flipped context whose units are mark units.
    static func draw(color: NSColor) {
        color.setFill()

        // "STR", centered, baseline at y = 11.6.
        let font = NSFont.systemFont(ofSize: 11.5, weight: .heavy)
        let kern: CGFloat = 0.3
        let text = NSAttributedString(string: "STR", attributes: [.font: font, .kern: kern, .foregroundColor: color])
        let width = text.size().width - kern // no tracking after the last letter
        let baseline: CGFloat = 11.6
        let origin = CGPoint(x: size.width / 2 - width / 2, y: baseline - font.ascender)
        text.draw(with: CGRect(origin: origin, size: CGSize(width: 40, height: 20)), options: [.usesLineFragmentOrigin])

        // The bar the letters stand on.
        NSBezierPath(roundedRect: CGRect(x: 1, y: 13.6, width: 25, height: 2.6), xRadius: 1.3, yRadius: 1.3).fill()
    }
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assets = root.appendingPathComponent("MTMR/Assets.xcassets")

// MARK: Menu-bar template (vector PDF)

func writeStatusPDF() throws {
    let url = assets.appendingPathComponent("StatusImage.imageset/StatusImage.pdf")
    var box = CGRect(origin: .zero, size: Mark.size)
    guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { throw NSError(domain: "pdf", code: 1) }
    ctx.beginPDFPage(nil)
    // Flip to the mark's y-down space.
    ctx.translateBy(x: 0, y: Mark.size.height)
    ctx.scaleBy(x: 1, y: -1)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    Mark.draw(color: .black) // template images use only the alpha channel
    NSGraphicsContext.restoreGraphicsState()
    ctx.endPDFPage()
    ctx.closePDF()

    let contents = """
    {
      "images" : [
        { "idiom" : "universal", "filename" : "StatusImage.pdf" }
      ],
      "info" : { "version" : 1, "author" : "xcode" },
      "properties" : {
        "preserves-vector-representation" : true,
        "template-rendering-intent" : "template"
      }
    }
    """
    try contents.write(to: assets.appendingPathComponent("StatusImage.imageset/Contents.json"), atomically: true, encoding: .utf8)
}

// MARK: App icon (PNG per size)

func writeAppIcon(pixels: Int) throws {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext
    let s = CGFloat(pixels) / 1024 // design on macOS's 1024 icon grid

    // Near-black squircle: 824 wide, inset 100, with a soft drop shadow.
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -10 * s), blur: 24 * s, color: NSColor(white: 0, alpha: 0.35).cgColor)
    NSColor(srgbRed: 0x14 / 255, green: 0x14 / 255, blue: 0x16 / 255, alpha: 1).setFill()
    NSBezierPath(roundedRect: CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s),
                 xRadius: 185 * s, yRadius: 185 * s).fill()
    cg.restoreGState()

    // The mark, white, centered and ~560 wide.
    let scale = 560 * s / Mark.size.width
    let w = Mark.size.width * scale, h = Mark.size.height * scale
    cg.saveGState()
    cg.translateBy(x: CGFloat(pixels) / 2 - w / 2, y: CGFloat(pixels) / 2 + h / 2)
    cg.scaleBy(x: scale, y: -scale) // into the mark's y-down space
    NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
    Mark.draw(color: NSColor(srgbRed: 0xF5 / 255, green: 0xF5 / 255, blue: 0xF7 / 255, alpha: 1))
    cg.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    let url = assets.appendingPathComponent("AppIcon.appiconset/logo-\(pixels).png")
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

try writeStatusPDF()
for pixels in [16, 32, 64, 128, 256, 512, 1024] {
    try writeAppIcon(pixels: pixels)
}
print("icons written")
