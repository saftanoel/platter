import AppKit

/// Renders the Platter app icon (a record on a cream plinth) at one size.
func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    let s = size
    // macOS icons sit in a rounded square inset from the canvas edge.
    let inset = s * 0.08
    let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let corner = rect.width * 0.22

    // Plinth: warm cream metal.
    let plinth = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)
    ctx.saveGState()
    ctx.addPath(plinth)
    ctx.clip()
    let colors = [
        NSColor(calibratedWhite: 0.95, alpha: 1).cgColor,
        NSColor(calibratedWhite: 0.78, alpha: 1).cgColor,
    ] as CFArray
    if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
        ctx.drawLinearGradient(
            grad,
            start: CGPoint(x: rect.minX, y: rect.maxY),
            end: CGPoint(x: rect.maxX, y: rect.minY),
            options: []
        )
    }
    ctx.restoreGState()

    // Record.
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let discR = rect.width * 0.37

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.008), blur: s * 0.03,
                  color: NSColor(calibratedWhite: 0, alpha: 0.45).cgColor)
    ctx.setFillColor(NSColor(calibratedWhite: 0.07, alpha: 1).cgColor)
    ctx.fillEllipse(in: CGRect(x: center.x - discR, y: center.y - discR, width: discR * 2, height: discR * 2))
    ctx.restoreGState()

    // Grooves.
    ctx.setLineWidth(max(0.5, s * 0.0035))
    var r = discR * 0.34
    var i = 0
    while r < discR * 0.96 {
        let alpha = i % 5 == 0 ? 0.20 : 0.10
        ctx.setStrokeColor(NSColor(calibratedWhite: 1, alpha: alpha).cgColor)
        ctx.strokeEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
        r += discR * 0.055
        i += 1
    }

    // Label.
    let labelR = discR * 0.30
    ctx.setFillColor(NSColor(calibratedRed: 0.86, green: 0.30, blue: 0.20, alpha: 1).cgColor)
    ctx.fillEllipse(in: CGRect(x: center.x - labelR, y: center.y - labelR, width: labelR * 2, height: labelR * 2))

    // Spindle.
    let spindleR = discR * 0.045
    ctx.setFillColor(NSColor(calibratedWhite: 0.97, alpha: 1).cgColor)
    ctx.fillEllipse(in: CGRect(x: center.x - spindleR, y: center.y - spindleR, width: spindleR * 2, height: spindleR * 2))

    // Specular sweep across the upper-left of the disc.
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: center.x - discR, y: center.y - discR, width: discR * 2, height: discR * 2))
    ctx.clip()
    let sheen = [
        NSColor(calibratedWhite: 1, alpha: 0.20).cgColor,
        NSColor(calibratedWhite: 1, alpha: 0).cgColor,
    ] as CFArray
    if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: sheen, locations: [0, 1]) {
        ctx.drawLinearGradient(
            grad,
            start: CGPoint(x: center.x - discR, y: center.y + discR),
            end: CGPoint(x: center.x + discR * 0.3, y: center.y - discR * 0.2),
            options: []
        )
    }
    ctx.restoreGState()

    image.unlockFocus()
    return image
}

func writePNG(_ image: NSImage, to path: String) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: URL(fileURLWithPath: path))
}

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "./AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

// (logical size, scale) pairs required for a complete .icns.
let specs: [(Int, Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
for (pt, scale) in specs {
    let px = pt * scale
    let img = drawIcon(size: CGFloat(px))
    let suffix = scale == 1 ? "" : "@2x"
    writePNG(img, to: "\(outDir)/icon_\(pt)x\(pt)\(suffix).png")
    print("icon_\(pt)x\(pt)\(suffix).png (\(px)px)")
}
