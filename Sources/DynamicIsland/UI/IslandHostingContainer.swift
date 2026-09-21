import AppKit
import SwiftUI
import QuartzCore

/// The panel's content view. Hosts the SwiftUI island and owns hover tracking.
///
/// Pass-through is the *panel's* job, via its frame -- `hitTest` cannot do it
/// (CLAUDE.md, "hitTest does not produce click pass-through"). The override here
/// is still worth keeping: it stops the app reacting to clicks in the shoulder
/// margin and, once the overlay is on, in the debug readout below the island.
@MainActor
final class IslandHostingContainer: NSView {

    private let controller: IslandController
    private var hosting: NSHostingView<IslandView>?
    private var trackingArea: NSTrackingArea?
    private var isHovering = false
    private var frameLink: CADisplayLink?
    private var lastFrameTimestamp: CFTimeInterval = 0

    /// Top-left origin, so island frames read the same way they are drawn.
    override var isFlipped: Bool { true }

    init(controller: IslandController) {
        self.controller = controller
        super.init(frame: CGRect(origin: .zero, size: controller.panelSize))

        // The panel resizes at transition boundaries. Between the resize and
        // SwiftUI's next draw, Core Animation has to show *something*, and by
        // default it stretches the stale contents with centre gravity -- the
        // island visibly drops to the middle of the new, taller panel and then
        // snaps back to the top. That reads as the island detaching from the
        // notch and growing upward into it.
        //
        // `.duringViewResize` forces a real redraw as the view resizes, and
        // `.topLeft` keeps any content that does slip through welded to the top
        // instead of drifting to the centre.
        wantsLayer = true
        layerContentsRedrawPolicy = .duringViewResize
        layerContentsPlacement = .topLeft

        let hosting = NSHostingView(rootView: IslandView(controller: controller))
        hosting.sizingOptions = []
        hosting.frame = bounds
        hosting.autoresizingMask = [.width, .height]
        hosting.wantsLayer = true
        hosting.layerContentsRedrawPolicy = .duringViewResize
        hosting.layerContentsPlacement = .topLeft
        addSubview(hosting)
        self.hosting = hosting
    }

    /// Belt and braces alongside the autoresizing mask: the hosting view must
    /// track the container exactly, or SwiftUI centres the island inside it.
    override func layout() {
        super.layout()
        if hosting?.frame != bounds { hosting?.frame = bounds }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used: no storyboards") }

    /// Called by the panel after it has resized.
    func geometryDidChange() {
        refreshTracking()
        syncDisplayLink()
    }

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

        // When the island grows under a cursor already inside it, say so, or
        // AppKit synthesises a second `mouseEntered`. Work out whether that is
        // actually the case rather than assuming either way.
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
        let windowPoint = window.convertPoint(fromScreen: NSEvent.mouseLocation)
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

    private func syncDisplayLink() {
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
        geometryDidChange()
    }
}
