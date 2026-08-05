import AppKit
import SwiftUI

/// The record, spun by Core Animation instead of by a timer.
///
/// The previous version ticked a `Timer` 30 times a second and pushed a new
/// `rotationEffect` angle into SwiftUI on every tick, which re-laid-out and re-composited
/// the whole scene each frame on every display. Here the disc is a plain `CALayer` with a
/// baked bitmap for contents, and the rotation is a single infinite `CABasicAnimation` on
/// `transform.rotation.z` — handed to the window server once, then advanced on the GPU
/// with no per-frame work on the main thread at all.
///
/// This needs to be a real AppKit view: a `rotationEffect` inside the SwiftUI tree is
/// re-evaluated by SwiftUI, so there is no way to hand the spin off to Core Animation
/// from inside it.
struct SpinningRecordView: NSViewRepresentable {
    let image: NSImage
    let isPlaying: Bool

    func makeNSView(context: Context) -> RecordLayerView {
        let view = RecordLayerView()
        view.discImage = image
        view.setSpinning(isPlaying)
        return view
    }

    func updateNSView(_ view: RecordLayerView, context: Context) {
        view.discImage = image
        view.setSpinning(isPlaying)
    }
}

final class RecordLayerView: NSView {
    /// 45°/s — a calm quarter of real 33⅓ speed. At true speed the record reads as a
    /// blur at wallpaper scale and pulls the eye away from the desk.
    private static let secondsPerRevolution: CFTimeInterval = 8

    private let disc = CALayer()
    private var wantsSpin = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(disc)
        disc.contentsGravity = .resizeAspect
        disc.masksToBounds = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unused") }

    /// Click-through: the scene sits at desktop level and must never eat a click meant
    /// for the desktop or an icon behind it.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    var discImage: NSImage? {
        didSet {
            guard discImage !== oldValue else { return }
            withoutImplicitAnimations {
                disc.contents = discImage?.cgImage(forProposedRect: nil, context: nil, hints: nil)
            }
        }
    }

    // MARK: Geometry

    /// The layer's `frame` is derived from its transform, so once the disc is rotated,
    /// setting `frame` would fight the animation. Drive `bounds` and `position` instead —
    /// those are transform-independent.
    override func layout() {
        super.layout()
        withoutImplicitAnimations {
            disc.bounds = CGRect(origin: .zero, size: bounds.size)
            disc.position = CGPoint(x: bounds.midX, y: bounds.midY)
            disc.contentsScale = window?.backingScaleFactor ?? 2
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        disc.contentsScale = window?.backingScaleFactor ?? 2
        // Detaching a layer from its window strips its animations; re-apply on return.
        applySpinState()
    }

    // MARK: Spin

    func setSpinning(_ spinning: Bool) {
        guard spinning != wantsSpin else { return }
        wantsSpin = spinning
        applySpinState()
    }

    private func applySpinState() {
        wantsSpin && window != nil ? startSpin() : stopSpin()
    }

    private func startSpin() {
        guard disc.animation(forKey: "spin") == nil else { return }
        let from = modelAngle

        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = from
        // Negative: Core Animation's positive z-rotation is counter-clockwise in an
        // unflipped layer, and records turn clockwise.
        spin.toValue = from - 2 * CGFloat.pi
        spin.duration = Self.secondsPerRevolution
        spin.repeatCount = .infinity
        spin.timingFunction = CAMediaTimingFunction(name: .linear)
        spin.isRemovedOnCompletion = false
        disc.add(spin, forKey: "spin")
    }

    /// Freezes the disc exactly where the eye last saw it: without lifting the angle out
    /// of the presentation layer first, pausing would snap the record back to its
    /// un-animated model angle.
    private func stopSpin() {
        guard disc.animation(forKey: "spin") != nil else { return }
        let stopped = presentedAngle ?? modelAngle
        disc.removeAnimation(forKey: "spin")
        withoutImplicitAnimations {
            disc.setValue(stopped, forKeyPath: "transform.rotation.z")
        }
    }

    private var modelAngle: CGFloat {
        disc.value(forKeyPath: "transform.rotation.z") as? CGFloat ?? 0
    }

    private var presentedAngle: CGFloat? {
        disc.presentation()?.value(forKeyPath: "transform.rotation.z") as? CGFloat
    }

    private func withoutImplicitAnimations(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }
}
