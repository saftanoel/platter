import AppKit

/// Pre-rendered, cached bitmaps for the parts of the scene that never change.
///
/// These were originally SwiftUI `Canvas` views, but a Canvas re-runs its draw closure
/// on every frame the enclosing view is invalidated — so spinning the record redrew the
/// wood grain, brushed metal and every groove 60 times a second across both displays.
/// Drawing them once into a texture turns that into a cheap blit.
enum SceneTextures {
    private static var cache: [String: NSImage] = [:]

    private static func cached(_ key: String, _ make: () -> NSImage) -> NSImage {
        if let hit = cache[key] { return hit }
        let image = make()
        cache[key] = image
        return image
    }

    /// Draws into a bitmap of an exact pixel size.
    ///
    /// `NSImage.lockFocus` renders at the display's backing scale, so on a Retina screen
    /// every one of these textures silently cost 4x the pixels it needed. These are soft,
    /// low-frequency backdrops that get scaled anyway, so 1:1 pixels are plenty.
    /// `pointSize` reports the image smaller than its pixel grid, i.e. renders it at a
    /// scale factor. Drawing coordinates stay in pixels either way.
    private static func bitmap(width: Int, height: Int, pointSize: NSSize? = nil, _ draw: (CGContext) -> Void) -> NSImage {
        let w = max(1, width), h = max(1, height)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ), let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
            return NSImage(size: NSSize(width: w, height: h))
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        draw(ctx.cgContext)
        NSGraphicsContext.restoreGraphicsState()

        let size = pointSize ?? NSSize(width: w, height: h)
        rep.size = size
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }

    /// Wood grain, figure and light shafts. Rendered at a capped resolution and stretched:
    /// the content is soft and low-frequency, so this is visually identical at a fraction
    /// of the memory a full-screen bitmap would need.
    static func woodDetail(aspect: CGFloat) -> NSImage {
        let key = "wood-\(String(format: "%.3f", aspect))"
        return cached(key) {
            let w: CGFloat = 1200
            let h = max(200, w / max(aspect, 0.2))
            let unit = min(w, h)
            return bitmap(width: Int(w), height: Int(h)) { ctx in

            // Figured blotches. Drawn as radial gradients that fade to clear so the
            // edges are soft without needing a separate blur pass.
            let space = CGColorSpaceCreateDeviceRGB()
            var i: CGFloat = 0
            while i < 26 {
                let fx = abs(sin(i * 12.9898)).truncatingRemainder(dividingBy: 1)
                let fy = abs(sin(i * 78.233)).truncatingRemainder(dividingBy: 1)
                let fr = abs(sin(i * 43.771)).truncatingRemainder(dividingBy: 1)
                let r = w * (0.04 + 0.06 * fr)
                let warm = i.truncatingRemainder(dividingBy: 2) == 0
                let core = warm
                    ? NSColor(calibratedRed: 0.55, green: 0.30, blue: 0.18, alpha: 0.16)
                    : NSColor(calibratedWhite: 0, alpha: 0.11)
                let colors = [core.cgColor, core.withAlphaComponent(0).cgColor] as CFArray
                guard let grad = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) else {
                    i += 1
                    continue
                }
                let centre = CGPoint(x: w * fx, y: h * fy)
                ctx.saveGState()
                // Squash vertically so the figure reads as elongated grain, not circles.
                ctx.translateBy(x: centre.x, y: centre.y)
                ctx.scaleBy(x: 1.0, y: 0.45)
                ctx.drawRadialGradient(grad, startCenter: .zero, startRadius: 0,
                                       endCenter: .zero, endRadius: r, options: [])
                ctx.restoreGState()
                i += 1
            }

            // Grain lines.
            ctx.setLineWidth(1)
            ctx.setStrokeColor(NSColor(calibratedWhite: 0, alpha: 0.07).cgColor)
            var y: CGFloat = 0
            var n: CGFloat = 0
            while y < h {
                let wobble = sin((y + n * 9) * 0.011) * unit * 0.012
                ctx.move(to: CGPoint(x: 0, y: y + wobble))
                ctx.addLine(to: CGPoint(x: w, y: y + wobble - unit * 0.006))
                ctx.strokePath()
                y += unit * 0.011
                n += 1
            }

            // Diagonal light shafts.
            let rayWidth = unit * 0.08
            let spacing = unit * 0.22
            ctx.setFillColor(NSColor(calibratedWhite: 0, alpha: 0.06).cgColor)
            var x: CGFloat = -h
            while x < w + h {
                ctx.beginPath()
                ctx.move(to: CGPoint(x: x, y: 0))
                ctx.addLine(to: CGPoint(x: x + rayWidth, y: 0))
                ctx.addLine(to: CGPoint(x: x + rayWidth + h, y: h))
                ctx.addLine(to: CGPoint(x: x + h, y: h))
                ctx.closePath()
                ctx.fillPath()
                x += spacing
            }
            }
        }
    }

    /// Fine vertical brushing for the plinth's metal top plate.
    static func brushedMetal(size: CGSize) -> NSImage {
        let key = "brushed-\(Int(size.width))x\(Int(size.height))"
        return cached(key) {
            bitmap(width: Int(size.width), height: Int(size.height)) { ctx in
            ctx.setLineWidth(0.6)
            var x: CGFloat = 0
            var i: CGFloat = 0
            while x < size.width {
                let f = abs(sin(i * 12.9898)).truncatingRemainder(dividingBy: 1)
                ctx.setStrokeColor(NSColor(calibratedWhite: 0, alpha: 0.008 + 0.026 * f).cgColor)
                ctx.move(to: CGPoint(x: x, y: 0))
                ctx.addLine(to: CGPoint(x: x, y: size.height))
                ctx.strokePath()
                x += 1.5
                i += 1
            }
            }
        }
    }

    /// The complete record — disc, grooves and centre label — as one bitmap so the
    /// spin can be a single GPU layer rotation. Cached against the current artwork.
    /// Keyed by diameter as well as artwork: each display renders at its own size, and a
    /// single-entry cache made the two displays evict each other on every update.
    private static var recordCache: [CGFloat: (key: String, image: NSImage)] = [:]

    /// The record is the one thing the eye actually lands on, and its grooves are the
    /// highest-frequency detail in the scene, so it is the one texture rendered above 1:1.
    private static let recordScale: CGFloat = 2

    /// `artworkID` identifies the artwork's content — see `Track.artworkID`. Keying this
    /// on the image object handed back a previous track's label after its address was
    /// recycled. Callers must pass an id alongside any artwork; the key stays a pure
    /// function of its inputs, because anything varying per call (a fresh UUID, a clock)
    /// would miss the cache on every frame and redraw the whole record 60 times a second.
    static func record(diameter: CGFloat, artwork: NSImage?, artworkID: String) -> NSImage {
        let artKey = artwork == nil ? "none" : artworkID
        let key = "record-\(Int(diameter))-\(artKey)"
        if let hit = recordCache[diameter], hit.key == key { return hit.image }

        // Everything below draws straight into this one context. An earlier version
        // composited a separate groove bitmap here; building it inside the draw nested
        // two graphics contexts, which corrupts the outer one and silently drops the
        // inner drawing entirely.
        let d = max(64, (diameter * recordScale).rounded())
        let space = CGColorSpaceCreateDeviceRGB()
        let image = bitmap(
            width: Int(d), height: Int(d),
            pointSize: NSSize(width: diameter, height: diameter)
        ) { ctx in
            let c = CGPoint(x: d / 2, y: d / 2)
            let outerR = d * 0.5
            let labelR = d * 0.150

            func ring(_ r: CGFloat) -> CGRect {
                CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
            }

            ctx.saveGState()
            ctx.addEllipse(in: ring(outerR))
            ctx.clip()

            // Disc body. Real black vinyl is nearly ink — a faintly warm charcoal that
            // falls off to almost nothing at the rim. All of the "grey" that reads as
            // vinyl comes from light bouncing off the grooves, never from the plastic,
            // so the body is kept genuinely dark and the sheen is layered on top.
            let body = [
                NSColor(calibratedRed: 0.086, green: 0.082, blue: 0.079, alpha: 1).cgColor,
                NSColor(calibratedRed: 0.052, green: 0.050, blue: 0.050, alpha: 1).cgColor,
                NSColor(calibratedRed: 0.022, green: 0.021, blue: 0.023, alpha: 1).cgColor,
            ] as CFArray
            if let grad = CGGradient(colorsSpace: space, colors: body, locations: [0, 0.74, 1]) {
                ctx.drawRadialGradient(grad, startCenter: c, startRadius: d * 0.07,
                                       endCenter: c, endRadius: outerR,
                                       options: [.drawsAfterEndLocation])
            }

            // Grooves. Each one is a dark valley with a thin lit crest on its outer wall:
            // the pair nets out darker than the plastic, which is what keeps the disc
            // black. The previous version stroked every groove in translucent *white*,
            // and at this spacing those strokes overlap — the disc was being washed with
            // a near-solid coat of white and came out mid-grey.
            // The pitch is held to whole pixels. A fractional pitch drifts the crest in
            // and out of phase with the pixel grid, and the groove field breaks up into
            // moiré bands instead of reading as an even texture.
            let pitch = max(3, (d * 0.0042).rounded())
            let runOut = labelR + pitch * 3          // smooth land between label and music
            var r = runOut
            var i = 0
            while r < outerR - pitch * 4 {
                ctx.setLineWidth(pitch * 0.55)
                ctx.setStrokeColor(NSColor(calibratedWhite: 0, alpha: 0.55).cgColor)
                ctx.strokeEllipse(in: ring(r))

                ctx.setLineWidth(pitch * 0.30)
                ctx.setStrokeColor(NSColor(calibratedWhite: 1, alpha: 0.115).cgColor)
                ctx.strokeEllipse(in: ring(r + pitch * 0.42))

                // Band gaps between tracks: unmodulated land, so they catch the light as
                // the bright concentric rings you can pick out across a record.
                if i % 38 == 0 && i > 0 {
                    ctx.setLineWidth(pitch * 0.6)
                    ctx.setStrokeColor(NSColor(calibratedWhite: 1, alpha: 0.13).cgColor)
                    ctx.strokeEllipse(in: ring(r - pitch * 0.5))
                }

                r += pitch
                i += 1
            }

            // Lead-in land at the rim and run-out land by the label: both smooth, both
            // glossier than the groove field.
            for landR in [outerR - pitch * 2.0, runOut - pitch * 1.4] {
                ctx.setLineWidth(pitch * 1.6)
                ctx.setStrokeColor(NSColor(calibratedWhite: 1, alpha: 0.045).cgColor)
                ctx.strokeEllipse(in: ring(landR))
            }

            // Rolled edge: a bright hairline right on the rim with shadow just inside it.
            ctx.setLineWidth(max(1, d * 0.004))
            ctx.setStrokeColor(NSColor(calibratedWhite: 0, alpha: 0.55).cgColor)
            ctx.strokeEllipse(in: ring(outerR - d * 0.008))
            ctx.setLineWidth(max(0.75, d * 0.0022))
            ctx.setStrokeColor(NSColor(calibratedWhite: 1, alpha: 0.16).cgColor)
            ctx.strokeEllipse(in: ring(outerR - d * 0.002))

            ctx.restoreGState()

            // Label. Kept near-black rather than paper cream: at this size the label is
            // a sixth of the disc, and a light one read as a hole punched through the
            // record instead of part of it. When there is artwork the sleeve *is* the
            // label — it fills the circle rather than floating in the middle of one.
            let labelRect = ring(labelR)
            ctx.saveGState()
            ctx.addEllipse(in: labelRect)
            ctx.clip()
            if let art = artwork {
                // Aspect-fill from the centre. Drawing the whole sleeve into a circular
                // clip would squash anything non-square, and sleeve art is square often
                // enough that a stretch is more obvious than a crop.
                let s = art.size
                let side = min(s.width, s.height)
                let src = CGRect(x: (s.width - side) / 2, y: (s.height - side) / 2,
                                 width: side, height: side)
                art.draw(in: labelRect, from: src, operation: .sourceOver, fraction: 1)
                // Print stock under the same light as the vinyl, not a lit screen.
                ctx.setFillColor(NSColor(calibratedWhite: 0, alpha: 0.14).cgColor)
                ctx.fill(labelRect)
            } else {
                let stock = [
                    NSColor(calibratedRed: 0.125, green: 0.120, blue: 0.115, alpha: 1).cgColor,
                    NSColor(calibratedRed: 0.042, green: 0.040, blue: 0.040, alpha: 1).cgColor,
                ] as CFArray
                if let grad = CGGradient(colorsSpace: space, colors: stock, locations: [0, 1]) {
                    ctx.drawRadialGradient(grad, startCenter: CGPoint(x: c.x - labelR * 0.3, y: c.y + labelR * 0.3),
                                           startRadius: 0, endCenter: c, endRadius: labelR * 1.25,
                                           options: [.drawsAfterEndLocation])
                }
            }
            ctx.restoreGState()

            // The label sits a hair below the vinyl, so it gets a contact shadow.
            ctx.setLineWidth(max(1, d * 0.003))
            ctx.setStrokeColor(NSColor(calibratedWhite: 0, alpha: 0.45).cgColor)
            ctx.strokeEllipse(in: ring(labelR + d * 0.0015))

            // Spindle hole: a punched hole, not a grey dot — dark, with the platter
            // catching a little light at its lower edge.
            let spindle = labelR * 0.11
            ctx.setFillColor(NSColor(calibratedWhite: 0.06, alpha: 1).cgColor)
            ctx.fillEllipse(in: ring(spindle))
            ctx.setLineWidth(max(0.75, d * 0.0018))
            ctx.setStrokeColor(NSColor(calibratedWhite: 1, alpha: 0.22).cgColor)
            ctx.strokeEllipse(in: ring(spindle * 1.12))
        }

        recordCache[diameter] = (key, image)
        return image
    }
}
