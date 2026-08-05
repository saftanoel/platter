import AppKit
import SwiftUI

/// The colours the desktop backdrop is built from, derived from the current cover art.
///
/// Stored as hue/saturation/brightness rather than as finished colours, purely so two
/// palettes can be blended sensibly — see `blending`.
struct ScenePalette: Equatable {
    var hue: Double
    var saturation: Double
    var brightness: Double

    /// Used when nothing is playing or the artwork yields nothing usable: a neutral
    /// slate that still reads as deliberate rather than as a failure to load.
    static let neutral = ScenePalette(hue: 0.61, saturation: 0.17, brightness: 0.24)

    var top: Color { Color(hue: hue, saturation: saturation, brightness: brightness) }

    var bottom: Color {
        Color(hue: hue, saturation: min(0.72, saturation * 1.12), brightness: brightness * 0.38)
    }

    var glow: Color {
        Color(hue: hue, saturation: saturation * 0.82, brightness: min(0.72, brightness * 1.75))
    }

    /// Walks the hue *around the wheel* instead of straight across colour space.
    ///
    /// Fading between two colours by any component-wise route — including a plain
    /// cross-dissolve, which is the same arithmetic — drags the midpoint toward grey,
    /// because the straight line between two saturated colours passes near the middle of
    /// the cube. Blue to orange spent half of every change looking like wet cardboard.
    /// Rotating the hue and carrying saturation across keeps the wallpaper a colour the
    /// whole way through.
    static func blending(_ from: ScenePalette, _ to: ScenePalette, _ t: Double) -> ScenePalette {
        let t = min(1, max(0, t))

        // A near-grey end has no meaningful hue to rotate towards, and spinning the wheel
        // on the way into or out of one looks like a fault. Hold the colourful end's hue.
        let greyLimit = 0.08
        let hue: Double
        if from.saturation < greyLimit {
            hue = to.hue
        } else if to.saturation < greyLimit {
            hue = from.hue
        } else {
            var delta = to.hue - from.hue
            if delta > 0.5 { delta -= 1 } else if delta < -0.5 { delta += 1 }
            hue = (from.hue + delta * t).truncatingRemainder(dividingBy: 1)
        }

        return ScenePalette(
            hue: hue < 0 ? hue + 1 : hue,
            saturation: from.saturation + (to.saturation - from.saturation) * t,
            brightness: from.brightness + (to.brightness - from.brightness) * t
        )
    }
}

/// Pulls the *background* colour out of a piece of cover art.
///
/// Deliberately not an average of the whole image: averaging a busy cover gives brown
/// mud every time. Sleeve backgrounds are overwhelmingly the colour sitting behind the
/// artwork's edges, so this samples a ring of border pixels, buckets them coarsely, and
/// takes the most populous bucket — the modal border colour. That survives a logo or a
/// face bleeding off one edge, which a mean does not.
enum ArtworkPalette {
    private static var cache: [String: ScenePalette] = [:]

    /// `id` must identify the artwork's *content*. An empty id means the caller has no
    /// stable identity to offer, so the cache is bypassed rather than risking a wrong hit.
    static func palette(for artwork: NSImage?, id: String) -> ScenePalette {
        guard let artwork else { return .neutral }
        if !id.isEmpty, let hit = cache[id] { return hit }

        let palette = colour(of: artwork).map(scene(from:)) ?? .neutral
        guard !id.isEmpty else { return palette }

        // Bounded: a long listening session would otherwise accumulate an entry per track.
        if cache.count > 24 { cache.removeAll() }
        cache[id] = palette
        return palette
    }

    // MARK: Sampling

    private static let sampleSide = 40

    /// One downsampled pixel, in OKLab.
    ///
    /// OKLab rather than HSB throughout. HSB's "saturation" is the ratio
    /// `(max - min) / max`, which explodes towards 1 as a pixel approaches black: a
    /// border measured at rgb(0.0013, 0.0006, 0.0006) — pure black to any eye — scored
    /// 0.55 saturation and handed over a hue of pure JPEG noise, which is how a black
    /// sleeve ended up with a maroon wallpaper. OKLab chroma is an absolute distance from
    /// the neutral axis, so black simply has none and drops out with no guard at all.
    /// It is also perceptually uniform, so equal distances look equally different, which
    /// is what makes clustering meaningful.
    private struct Sample {
        var L: Double
        var a: Double
        var b: Double
        var onBorder: Bool

        var chroma: Double { (a * a + b * b).squareRoot() }
    }

    private struct Cluster {
        var centre: Sample
        var count = 0
        var borderCount = 0
    }

    /// Picks the colour a person would name if handed the sleeve and asked what colour it
    /// is. Every region of the cover is *scored* and the best one wins.
    ///
    /// This replaced a cascade of if/else branches with hand-tuned thresholds, which had
    /// to be patched three times in a row: each threshold is a cliff, and real covers land
    /// on both sides of it. As weights in one expression the same instincts degrade
    /// gracefully instead — a sleeve that is sixty percent flat background and forty
    /// percent vivid subject gets weighed, rather than forced down one path.
    private static func colour(of artwork: NSImage) -> NSColor? {
        guard let pixels = downsample(artwork, to: sampleSide) else { return nil }
        let samples = samples(from: pixels)
        guard !samples.isEmpty else { return nil }

        let clusters = cluster(samples, into: 5)
        guard let biggest = clusters.max(by: { $0.count < $1.count }) else { return nil }

        let total = Double(samples.count)
        let borderTotal = Double(max(1, samples.lazy.filter(\.onBorder).count))

        var best: (score: Double, centre: Sample)?
        for c in clusters where c.count > 0 {
            let area = Double(c.count) / total
            // Chroma saturates: past roughly 0.14 in OKLab a colour is already vivid, and
            // scoring beyond that just lets one neon detail outvote the whole sleeve.
            let colourfulness = min(1, c.centre.chroma / 0.14)
            let usableTone = lightnessWindow(c.centre.L)
            // "Designed sleeves keep their background at the edges" as a preference, not
            // a branch. A region owning the border ring is favoured, never guaranteed.
            let borderBonus = 1 + 1.4 * (Double(c.borderCount) / borderTotal)

            let score = area * colourfulness * usableTone * borderBonus
            if score > (best?.score ?? 0) { best = (score, c.centre) }
        }

        // A genuinely monochrome sleeve — a black and white photograph — scores nothing
        // anywhere. Hand back its dominant region and let the shaping stage render it as
        // a light or dark neutral, which is the honest answer for a colourless cover.
        guard let winner = best, winner.score > 0.004 else { return srgb(from: biggest.centre) }
        return srgb(from: winner.centre)
    }

    /// Penalises near-black and near-white on a curve rather than at a cliff, so a cover
    /// sitting near the edge of usable range degrades instead of flipping.
    private static func lightnessWindow(_ L: Double) -> Double {
        func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
            let t = min(1, max(0, (x - edge0) / (edge1 - edge0)))
            return t * t * (3 - 2 * t)
        }
        return smoothstep(0.10, 0.28, L) * (1 - smoothstep(0.86, 0.99, L))
    }

    // MARK: Clustering

    /// k-means in OKLab. Seeded from evenly spaced lightness quantiles rather than at
    /// random, so the same cover always yields the same wallpaper.
    private static func cluster(_ samples: [Sample], into k: Int) -> [Cluster] {
        let byLightness = samples.sorted { $0.L < $1.L }
        var centres: [Sample] = (0..<k).map { i in
            let q = (Double(i) + 0.5) / Double(k)
            return byLightness[min(byLightness.count - 1, Int(q * Double(byLightness.count)))]
        }

        var tallies = [(L: Double, a: Double, b: Double, n: Int, border: Int)](
            repeating: (0, 0, 0, 0, 0), count: k)

        for _ in 0..<12 {
            tallies = Array(repeating: (0, 0, 0, 0, 0), count: k)
            for s in samples {
                var nearest = 0
                var shortest = Double.infinity
                for (i, c) in centres.enumerated() {
                    let dL = s.L - c.L, da = s.a - c.a, db = s.b - c.b
                    let d = dL * dL + da * da + db * db
                    if d < shortest { shortest = d; nearest = i }
                }
                tallies[nearest].L += s.L
                tallies[nearest].a += s.a
                tallies[nearest].b += s.b
                tallies[nearest].n += 1
                if s.onBorder { tallies[nearest].border += 1 }
            }
            for i in 0..<k where tallies[i].n > 0 {
                let n = Double(tallies[i].n)
                centres[i] = Sample(L: tallies[i].L / n, a: tallies[i].a / n, b: tallies[i].b / n,
                                    onBorder: false)
            }
        }

        return (0..<k).map { Cluster(centre: centres[$0], count: tallies[$0].n, borderCount: tallies[$0].border) }
    }

    // MARK: Colour space

    private static func samples(from pixels: [UInt8]) -> [Sample] {
        let n = sampleSide
        var out: [Sample] = []
        out.reserveCapacity(n * n)
        for y in 0..<n {
            for x in 0..<n {
                let i = (y * n + x) * 4
                var s = oklab(Double(pixels[i]) / 255, Double(pixels[i + 1]) / 255, Double(pixels[i + 2]) / 255)
                s.onBorder = x < 2 || y < 2 || x >= n - 2 || y >= n - 2
                out.append(s)
            }
        }
        return out
    }

    private static func toLinear(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    private static func toGamma(_ c: Double) -> Double {
        c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055
    }

    private static func oklab(_ sr: Double, _ sg: Double, _ sb: Double) -> Sample {
        let r = toLinear(sr), g = toLinear(sg), b = toLinear(sb)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return Sample(
            L: 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            a: 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            b: 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s,
            onBorder: false
        )
    }

    private static func srgb(from sample: Sample) -> NSColor {
        let l = pow(sample.L + 0.3963377774 * sample.a + 0.2158037573 * sample.b, 3)
        let m = pow(sample.L - 0.1055613458 * sample.a - 0.0638541728 * sample.b, 3)
        let s = pow(sample.L - 0.0894841775 * sample.a - 1.2914855480 * sample.b, 3)

        func clamp(_ v: Double) -> CGFloat { CGFloat(min(1, max(0, v))) }
        return NSColor(
            calibratedRed: clamp(toGamma(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s)),
            green: clamp(toGamma(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s)),
            blue: clamp(toGamma(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)),
            alpha: 1
        )
    }

#if HARNESS
    /// Reports what the scorer chose and why, for the offline verification harness.
    /// Compiled out of the shipping build.
    static func diagnose(_ artwork: NSImage) -> (branch: String, border: NSColor?, palette: ScenePalette) {
        guard let pixels = downsample(artwork, to: sampleSide) else { return ("no-pixels", nil, .neutral) }
        let all = samples(from: pixels)
        let clusters = cluster(all, into: 5)
        let picked = colour(of: artwork)

        let winner = clusters.min { a, b in
            guard let picked = picked?.usingColorSpace(.deviceRGB) else { return true }
            let target = oklab(Double(picked.redComponent), Double(picked.greenComponent), Double(picked.blueComponent))
            func dist(_ c: Cluster) -> Double {
                let dL = c.centre.L - target.L, da = c.centre.a - target.a, db = c.centre.b - target.b
                return dL * dL + da * da + db * db
            }
            return dist(a) < dist(b)
        }
        let chroma = winner?.centre.chroma ?? 0
        let share = Double(winner?.count ?? 0) / Double(max(1, all.count))
        let label = chroma < 0.02 ? "monochrome" : String(format: "scored C=%.3f area=%.2f", chroma, share)
        return (label, picked, palette(for: artwork, id: ""))
    }
#endif

    /// Artwork arrives at whatever size the player hands over, so it is squashed into a
    /// small fixed grid first — that also averages away JPEG noise for free.
    private static func downsample(_ image: NSImage, to side: Int) -> [UInt8]? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: side * 4, bitsPerPixel: 32
        ), let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        ctx.imageInterpolation = .medium
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side),
                   from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()

        guard let data = rep.bitmapData else { return nil }
        return Array(UnsafeBufferPointer(start: data, count: side * side * 4))
    }

    // MARK: Shaping

    /// Covers run from black sleeves to blown-out white ones, and neither works as a
    /// wallpaper as-is: one swallows the turntable's shadow, the other glares. The hue is
    /// kept exactly as sampled and only saturation and brightness are pulled into a band
    /// the scene can sit on.
    private static func scene(from sampled: NSColor) -> ScenePalette {
        guard let rgb = sampled.usingColorSpace(.deviceRGB) else { return .neutral }

        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        rgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)

        // Near-greys keep a whisper of their tint rather than being forced colourful.
        let saturation = min(0.62, s < 0.06 ? s : max(0.16, s * 0.78))
        let brightness = min(0.42, max(0.13, b * 0.62 + 0.06))

        return ScenePalette(hue: Double(h), saturation: Double(saturation), brightness: Double(brightness))
    }
}

extension Color {
    init(hue: Double, saturation: Double, brightness: Double) {
        self.init(NSColor(calibratedHue: hue, saturation: saturation, brightness: brightness, alpha: 1))
    }
}
