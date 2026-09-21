import AppKit

/// One borderless, non-activating panel per screen. Sized once to the maximum
/// expanded bounds and never resized -- the island morphs *inside* it.
@MainActor
final class IslandPanel: NSPanel {

    static let islandLevel = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
    static let islandCollectionBehavior: NSWindow.CollectionBehavior =
        [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

    init(screen: NSScreen, controller: IslandController) {
        super.init(
            contentRect: CGRect(origin: .zero, size: IslandMetrics.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        // Pass-through is the content view's job, via hitTest. Flipping this
        // would make the island itself unclickable.
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true

        applyWindowRules()

        contentView = IslandHostingContainer(controller: controller)
        reposition(on: screen, notch: controller.notch)
    }

    /// Never take key or main: hovering the island must not disturb whatever the
    /// user is actually working in.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Window level and collection behaviour can be lost across sleep/wake, so
    /// this is re-applied rather than only set at construction.
    func applyWindowRules() {
        level = Self.islandLevel
        collectionBehavior = Self.islandCollectionBehavior
    }

    func reposition(on screen: NSScreen, notch: NotchGeometry) {
        let size = IslandMetrics.panelSize
        // Centred on the notch, not the screen: they differ, and on synthetic
        // notches the distinction is the whole ball game.
        let origin = CGPoint(x: notch.rect.midX - size.width / 2,
                             y: screen.frame.maxY - size.height)
        setFrame(CGRect(origin: origin, size: size), display: true)
    }
}
