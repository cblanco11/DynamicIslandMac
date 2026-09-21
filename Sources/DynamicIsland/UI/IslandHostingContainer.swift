import AppKit
import SwiftUI
import QuartzCore

/// The panel's content view. Two jobs:
///
/// 1. **Pass-through.** `hitTest` returns nil everywhere outside the island, so
///    clicks reach whatever is underneath. `ignoresMouseEvents` is never
///    toggled -- that would make the island itself unclickable too.
/// 2. **Hover.** One `NSTrackingArea`, resized to follow the island, with
///    `.activeAlways` because an `LSUIElement` app is never the active app.
///    No global event monitor: nothing fires while the cursor is elsewhere.
@MainActor
final class IslandHostingContainer: NSView {

    private let controller: IslandController
    private var trackingArea: NSTrackingArea?
    private var isHovering = false
    private var frameLink: CADisplayLink?
    private var lastFrameTimestamp: CFTimeInterval = 0

    /// Top-left origin, so island frames read the same way they are drawn.
    override var isFlipped: Bool { true }

    init(controller: IslandController) {
        self.controller = controller
        super.init(frame: CGRect(origin: .zero, size: IslandMetrics.panelSize))

        let hosting = NSHostingView(rootView: IslandView(controller: controller))
        hosting.frame = bounds
        hosting.autoresizingMask = [.width, .height]
        addSubview(hosting)

        controller.onGeometryChange = { [weak self] in
            self?.refreshTracking()
            self?.syncDisplayLink()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used: no storyboards") }

    // MARK: - Pass-through

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard controller.interactiveFrame.contains(local) else { return nil }
        return super.hitTest(point)
    }

    // MARK: - Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        refreshTracking()
    }

    private func refreshTracking() {
        let rect = controller.interactiveFrame
        if let existing = trackingArea {
            guard existing.rect != rect else { return }
            removeTrackingArea(existing)
        }

        var options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways]

        // When the island grows under a cursor that is already inside it, tell
        // AppKit so it does not synthesise a second `mouseEntered`. Work out
        // whether that is actually true rather than assuming either way.
        let cursorInside = cursorPointInSelf().map(rect.contains) ?? false
        if cursorInside { options.insert(.assumeInside) }
        isHovering = cursorInside

        let area = NSTrackingArea(rect: rect, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    /// Current cursor position in this view's coordinates. A one-shot read of
    /// `NSEvent.mouseLocation`, not a poll.
    private func cursorPointInSelf() -> NSPoint? {
        guard let window else { return nil }
        let screenPoint = NSEvent.mouseLocation
        let windowPoint = window.convertPoint(fromScreen: screenPoint)
        return convert(windowPoint, from: nil)
    }

    override func mouseEntered(with event: NSEvent) {
        guard !isHovering else { return }
        isHovering = true
        controller.mouseEntered()
    }

    override func mouseExited(with event: NSEvent) {
        guard isHovering else { return }
        isHovering = false
        controller.mouseExited()
    }

    // MARK: - Frame rate (debug overlay only)

    func syncDisplayLink() {
        if controller.debugOverlayEnabled {
            guard frameLink == nil else { return }
            let link = displayLink(target: self, selector: #selector(tick(_:)))
            link.add(to: .main, forMode: .common)
            frameLink = link
        } else {
            frameLink?.invalidate()
            frameLink = nil
            lastFrameTimestamp = 0
            controller.frameRate = 0
        }
    }

    @objc private func tick(_ link: CADisplayLink) {
        defer { lastFrameTimestamp = link.timestamp }
        guard lastFrameTimestamp > 0 else { return }
        let delta = link.timestamp - lastFrameTimestamp
        guard delta > 0 else { return }
        // Light smoothing so the readout is legible rather than jittering.
        let instantaneous = 1.0 / delta
        controller.frameRate = controller.frameRate == 0
            ? instantaneous
            : controller.frameRate * 0.9 + instantaneous * 0.1
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshTracking()
        syncDisplayLink()
    }
}
