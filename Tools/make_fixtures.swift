import AppKit

/// Synthesizes cover-art fixtures for the render harness, chosen to stress
/// ArtworkPalette's border-ring modal-colour logic (see ScenePalette.swift):
///
///   - busy-colourful: no single dominant border colour, many saturated regions.
///   - monochrome-photo: zero chroma everywhere — exercises the "no winner" fallback.
///   - light-border-ring: a near-white frame around a vivid centre, testing the
///     upper-lightness penalty against the border bonus.
///   - dark-border-ring: a near-black frame around a vivid centre — the exact shape of
///     bug that used to turn a black sleeve into a maroon wallpaper under HSB, before the
///     OKLab rewrite (a pure-black border has zero chroma, not high saturation).
///
/// Run with: swift Tools/make_fixtures.swift [outDir]

let side: CGFloat = 320

func image(_ draw: (CGContext) -> Void) -> NSImage {
    let img = NSImage(size: NSSize(width: side, height: side))
    img.lockFocus()
    if let ctx = NSGraphicsContext.current?.cgContext {
        draw(ctx)
    }
    img.unlockFocus()
    return img
}

func writePNG(_ image: NSImage, to path: String) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: URL(fileURLWithPath: path))
}

// MARK: - busy-colourful

/// A grid of saturated tiles running edge to edge, including the border ring, so no
/// single colour dominates and the picker has to fall back on area/chroma weighting.
func busyColourful() -> NSImage {
    image { ctx in
        let hues: [CGFloat] = [0.0, 0.08, 0.14, 0.33, 0.55, 0.62, 0.78, 0.92]
        let cols = 8
        let tile = side / CGFloat(cols)
        for row in 0..<cols {
            for col in 0..<cols {
                let hue = hues[(row * cols + col) % hues.count]
                NSColor(calibratedHue: hue, saturation: 0.85, brightness: 0.9, alpha: 1).setFill()
                ctx.fill(CGRect(x: CGFloat(col) * tile, y: CGFloat(row) * tile, width: tile, height: tile))
            }
        }
    }
}

// MARK: - monochrome-photo

/// A pure grayscale radial gradient — R=G=B everywhere, so every sample has zero chroma
/// in OKLab regardless of lightness.
func monochromePhoto() -> NSImage {
    image { ctx in
        let colors = [
            NSColor(calibratedWhite: 0.82, alpha: 1).cgColor,
            NSColor(calibratedWhite: 0.30, alpha: 1).cgColor,
        ] as CFArray
        guard let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceGray(), colors: colors, locations: [0, 1]) else { return }
        ctx.drawRadialGradient(
            grad,
            startCenter: CGPoint(x: side * 0.5, y: side * 0.5), startRadius: 0,
            endCenter: CGPoint(x: side * 0.5, y: side * 0.5), endRadius: side * 0.72,
            options: [.drawsAfterEndLocation]
        )
    }
}

// MARK: - light-border-ring

/// A cream border ring around a vivid, dark-saturated centre — the border should win on
/// area and the border bonus despite scoring low on colourfulness.
func lightBorderRing() -> NSImage {
    image { ctx in
        NSColor(calibratedWhite: 0.94, alpha: 1).setFill()
        ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))

        let inset = side * 0.16
        NSColor(calibratedHue: 0.02, saturation: 0.82, brightness: 0.55, alpha: 1).setFill()
        ctx.fillEllipse(in: CGRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2))
    }
}

// MARK: - dark-border-ring

/// A near-black border ring around a vivid centre. Pre-OKLab this reliably produced a
/// wrong-hued wallpaper: HSB saturation explodes near black, so the border scored as if
/// it were the most saturated region on the cover.
func darkBorderRing() -> NSImage {
    image { ctx in
        NSColor(calibratedWhite: 0.02, alpha: 1).setFill()
        ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))

        let inset = side * 0.16
        NSColor(calibratedHue: 0.55, saturation: 0.75, brightness: 0.62, alpha: 1).setFill()
        ctx.fillEllipse(in: CGRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2))
    }
}

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "./Fixtures"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let fixtures: [(String, () -> NSImage)] = [
    ("busy-colourful", busyColourful),
    ("monochrome-photo", monochromePhoto),
    ("light-border-ring", lightBorderRing),
    ("dark-border-ring", darkBorderRing),
]

for (name, make) in fixtures {
    let path = "\(outDir)/\(name).png"
    writePNG(make(), to: path)
    print(path)
}
