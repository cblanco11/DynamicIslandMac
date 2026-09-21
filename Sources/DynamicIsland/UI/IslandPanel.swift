import AppKit

/// One borderless, non-activating panel per screen.
///
/// The panel's frame **is** the interactive region. The window server routes
/// clicks by window frame -- not by AppKit view hit testing, and not by alpha
/// (see CLAUDE.md, "hitTest does not produce click pass-through") -- so the only
/// way for clicks to reach the app underneath is for no window to be there.
///
/// It is therefore resized to track the island, but only at transition
/// boundaries: it jumps to the target size before the shape starts growing and
/// shrinks only once the shape has finished collapsing. Two resizes per hover
/// cycle, never per frame, so the morph itself stays a single uninterrupted
/// geometry animation inside a stationary window.
@MainActor
final class IslandPanel: NSPanel {

    static let islandLevel = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
    static let islandCollectionBehavior: NSWindow.CollectionBehavior =
        [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

    private let controller: IslandController
    private var screenFrame: CGRect

    init(screen: NSScreen, controller: IslandController) {
        self.controller = controller
        self.screenFrame = screen.frame

        super.init(
            contentRect: CGRect(origin: .zero, size: controller.panelSize),
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
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true

        applyWindowRules()

        let container = IslandHostingContainer(controller: controller)
        contentView = container

        controller.onGeometryChange = { [weak self] in
            self?.syncGeometry()
        }

        syncGeometry()
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

    func reposition(on screen: NSScreen) {
        screenFrame = screen.frame
        syncGeometry()
    }

    /// Resize and reposition to match the controller, then let the container
    /// refresh its tracking area against the new bounds.
    private func syncGeometry() {
        let size = controller.panelSize
        // Centred on the notch, not the screen: they differ, and on synthetic
        // notches the distinction is the whole ball game.
        let origin = CGPoint(x: controller.notch.rect.midX - size.width / 2,
                             y: screenFrame.maxY - size.height)
        let target = CGRect(origin: origin, size: size)

        if frame != target {
            setFrame(target, display: true)
        }
        (contentView as? IslandHostingContainer)?.geometryDidChange()
    }
}
