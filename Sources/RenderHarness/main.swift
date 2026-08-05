import AppKit
import SwiftUI

/// Renders DesktopSceneView off-screen for a set of fixture covers, so the scene's look
/// can be judged from a PNG instead of by screenshotting the live desktop. Compiled only
/// into the RenderHarness target (SWIFT_ACTIVE_COMPILATION_CONDITIONS: HARNESS), which is
/// what lights up NowPlayingPoller.stageTrack and ArtworkPalette.diagnose.
///
/// Usage: RenderHarness [fixturesDir] [outDir]  (defaults: Fixtures, renders — both
/// relative to the working directory scripts/render.sh runs this from, the repo root)

@MainActor
private func renderView(_ view: NSView, scale: CGFloat) -> NSBitmapImageRep? {
    // NSView.cacheDisplay(in:to:) is the sanctioned way to rasterize a layer-backed view
    // hierarchy off-screen: it handles the AppKit-vs-Core-Animation coordinate flip
    // internally, which a hand-rolled CGContext + layer.render(in:) would not.
    let size = view.bounds.size
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int((size.width * scale).rounded()),
        pixelsHigh: Int((size.height * scale).rounded()),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }
    // Reporting a smaller point size than the pixel grid is what tells cacheDisplay to
    // render at that density instead of 1x.
    rep.size = size
    view.cacheDisplay(in: view.bounds, to: rep)
    return rep
}

@MainActor
private func run() {
    let args = CommandLine.arguments
    let fixturesDir = args.count > 1 ? args[1] : "Fixtures"
    let outDir = args.count > 2 ? args[2] : "renders"

    guard let entries = try? FileManager.default.contentsOfDirectory(atPath: fixturesDir) else {
        FileHandle.standardError.write("Could not read fixtures dir '\(fixturesDir)'\n".data(using: .utf8)!)
        exit(1)
    }
    let fixtures = entries.filter { $0.hasSuffix(".png") || $0.hasSuffix(".jpg") }.sorted()
    guard !fixtures.isEmpty else {
        FileHandle.standardError.write("No fixture images (.png/.jpg) found in '\(fixturesDir)'\n".data(using: .utf8)!)
        exit(1)
    }

    try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

    // A representative laptop-scale desktop. The exact size doesn't matter for judging
    // the look — DesktopSceneView derives every metric from it as a ratio.
    let captureSize = CGSize(width: 1680, height: 1050)

    for name in fixtures {
        let path = "\(fixturesDir)/\(name)"
        guard let artwork = NSImage(contentsOfFile: path) else {
            print("skip \(name): could not load")
            continue
        }
        let stem = (name as NSString).deletingPathExtension

        // Stage the track on a fresh poller *before* the scene ever appears, so
        // DesktopSceneView's onAppear sets fadeFrom/fadeTo/fade to their settled final
        // values directly. Staging into an already-visible scene instead would change
        // `palette` after onAppear and go through crossFade()'s 1.6s withAnimation path —
        // which needs real per-frame ticks to resolve and may never progress on a window
        // that's never ordered on screen, leaving a stuck, undefined intermediate colour.
        let poller = NowPlayingPoller()
        poller.stageTrack(Track(
            title: stem, artist: "Harness", album: stem,
            isPlaying: true, artwork: artwork, artworkID: stem
        ))
        let settings = Settings()

        let hosting = NSHostingView(rootView: DesktopSceneView(poller: poller, settings: settings, size: captureSize))
        hosting.frame = NSRect(origin: .zero, size: captureSize)

        // Never ordered on screen — assigning it as a window's contentView is what gives
        // the custom NSView/CALayer plumbing (RecordLayerView's window-dependent spin
        // setup, the scale lookup in layout()) a real window to attach to.
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: captureSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting

        // Let SwiftUI's first reconciliation pass (body evaluation, onAppear) land.
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        hosting.layoutSubtreeIfNeeded()

        let diagnosis = ArtworkPalette.diagnose(artwork)
        print("\(stem): \(diagnosis.branch)")

        guard let rep = renderView(hosting, scale: 2),
              let png = rep.representation(using: .png, properties: [:]) else {
            print("  render failed")
            continue
        }
        let outPath = "\(outDir)/\(stem).png"
        try? png.write(to: URL(fileURLWithPath: outPath))
        print("  -> \(outPath)")
    }
}

MainActor.assumeIsolated { run() }
