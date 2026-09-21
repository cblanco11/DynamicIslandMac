import AppKit
import SwiftUI
import Observation
import os

/// Owns the island's state machine, hover timing and panel geometry for a single
/// screen. Views read it; nothing else mutates it.
@MainActor
@Observable
final class IslandController {

    private(set) var state: IslandState = .closed
    private(set) var notch: NotchGeometry

    /// True from the moment a morph starts until it has settled.
    private(set) var isMorphing = false

    private(set) var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    /// Debug readout only; stays 0 unless the overlay is on.
    var frameRate: Double = 0

    var debugOverlayEnabled = UserDefaults.standard.bool(forKey: "DIDebugOverlay") {
        didSet {
            UserDefaults.standard.set(debugOverlayEnabled, forKey: "DIDebugOverlay")
            onGeometryChange?()
        }
    }

    /// Fired whenever `panelSize` or `interactiveFrame` changes, so the panel can
    /// resize and the container can refresh its tracking area.
    var onGeometryChange: (@MainActor () -> Void)?

    /// Transport commands from the island's controls, routed back to whoever
    /// owns the media provider.
    var onTransport: (@MainActor (MediaRemoteHelper.Command) -> Void)?

    /// The panel is held at least this large regardless of the current state.
    ///
    /// This is how "never resize the window while the morph is running" is
    /// enforced: the reservation is taken *before* a transition, the window
    /// resizes while nothing is animating, and it is only released once the
    /// morph has fully settled. See CLAUDE.md.
    ///
    /// Deliberately **observed**: `panelSize` derives from it, so hiding it from
    /// observation stops SwiftUI re-laying out when the panel grows, and
    /// `NSHostingView` then centres the stale, smaller content in the new bounds
    /// -- the island visibly unpins from the notch.
    private var reservation: CGSize?

    @ObservationIgnored private var hoverTask: Task<Void, Never>?
    @ObservationIgnored private var morphTask: Task<Void, Never>?
    @ObservationIgnored private var reduceMotionObserver: NSObjectProtocol?
    @ObservationIgnored private static let log =
        Logger(subsystem: "com.jeffreyotoo.DynamicIsland", category: "state")

    init(notch: NotchGeometry) {
        self.notch = notch
        reduceMotionObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            }
        }
    }

    func tearDown() {
        hoverTask?.cancel(); morphTask?.cancel()
        hoverTask = nil; morphTask = nil
        onGeometryChange = nil; onTransport = nil
        if let reduceMotionObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(reduceMotionObserver)
            self.reduceMotionObserver = nil
        }
    }

    func update(notch: NotchGeometry) {
        guard notch != self.notch else { return }
        self.notch = notch
        onGeometryChange?()
    }

    // MARK: - Sizes

    var closedSize: CGSize { notch.rect.size }

    var peekSize: CGSize {
        CGSize(width: notch.rect.width + 2 * IslandMetrics.peekExtension,
               height: notch.rect.height)
    }

    var hoverSize: CGSize {
        CGSize(width: notch.rect.width + 2 * IslandMetrics.hoverExtension,
               height: IslandMetrics.hoverHeight)
    }

    func size(for state: IslandState) -> CGSize {
        switch state {
        case .closed:   closedSize
        case .peek:     peekSize
        case .hover:    hoverSize
        case .expanded: IslandMetrics.expandedSize
        }
    }

    var currentSize: CGSize { size(for: state) }

    private var containedSize: CGSize {
        guard let reservation else { return currentSize }
        return CGSize(width: max(currentSize.width, reservation.width),
                      height: max(currentSize.height, reservation.height))
    }

    /// The panel's size. The panel frame *is* the interactive region: the window
    /// server routes clicks by frame, so anything the panel covers is a click
    /// the app underneath does not get.
    var panelSize: CGSize {
        let island = containedSize
        return CGSize(
            width: island.width + 2 * IslandMetrics.shoulderRadius,
            height: island.height + (debugOverlayEnabled ? IslandMetrics.debugOverlayHeight : 0)
        )
    }

    /// The island's frame inside the panel: centred, pinned to the top edge.
    var islandFrame: CGRect {
        let size = currentSize
        return CGRect(x: (panelSize.width - size.width) / 2, y: 0,
                      width: size.width, height: size.height)
    }

    /// What the tracking area covers. Grown to the reservation while morphing so
    /// a fast hover-out cannot fall through a gap and strand the island open.
    var interactiveFrame: CGRect {
        let resting = islandFrame
        guard isMorphing, let reservation else { return resting }
        let wide = CGRect(x: (panelSize.width - reservation.width) / 2, y: 0,
                          width: reservation.width, height: reservation.height)
        return resting.union(wide)
    }

    // MARK: - Animation

    var animation: Animation {
        reduceMotion
            ? .easeOut(duration: IslandMetrics.reducedMotionDuration.seconds)
            : .spring(IslandMetrics.morphSpring)
    }

    // MARK: - Activities

    /// What the island is showing when it is not being hovered. Observed: the
    /// expanded view renders it too, since `.expanded` carries no payload.
    private(set) var restingActivity: Activity?

    func present(_ activity: Activity?) {
        restingActivity = activity
        // An open player or an active hover wins; the new activity is picked up
        // when the user moves away.
        switch state {
        case .expanded:
            return
        case .hover:
            if let activity { transition(to: .hover(activity)) } else { transition(to: .closed) }
        case .closed, .peek:
            transition(to: restingState)
        }
    }

    /// The activity the island should draw, in any state.
    var displayedActivity: Activity? { state.activity ?? restingActivity }

    /// Tint for the current activity, supplied by whoever owns the providers.
    var tint: NSColor = ArtworkColor.fallback

    private var restingState: IslandState {
        restingActivity.map { IslandState.peek($0) } ?? .closed
    }

    // MARK: - Hover

    func mouseEntered() {
        // Nothing to show means nothing to hint at; the island stays inert.
        guard let activity = restingActivity else { return }
        // Reserve the hover panel now, while nothing is animating.
        reserve(hoverSize)
        scheduleHover(after: IslandMetrics.hoverInDelay) { $0.transition(to: .hover(activity)) }
    }

    func mouseExited() {
        scheduleHover(after: IslandMetrics.hoverOutDelay) { $0.transition(to: $0.restingState) }
    }

    /// A click on the island opens the full player, and closes it again.
    ///
    /// Deliberately separate from hover: hovering the top of the screen is
    /// something people do by accident all day, so the full player is only ever
    /// a decision.
    func islandClicked() {
        hoverTask?.cancel()
        switch state {
        case .expanded:
            transition(to: restingActivity.map { IslandState.hover($0) } ?? .closed)
        case .peek, .hover:
            transition(to: .expanded)
        case .closed:
            break
        }
    }

    private func scheduleHover(after delay: Duration,
                               _ body: @escaping @MainActor (IslandController) -> Void) {
        hoverTask?.cancel()
        hoverTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            body(self)
        }
    }

    // MARK: - Transitions

    /// Grow the panel if needed, let that resize land, *then* animate. A window
    /// resize that overlaps the morph makes Core Animation composite the stale
    /// backing store with centre gravity, which visibly unpins the island from
    /// the notch.
    private func transition(to next: IslandState) {
        guard next != state else { return }

        if reserve(size(for: next)) {
            Task { [weak self] in
                // One display tick, so the resize is committed before we animate.
                try? await Task.sleep(for: .milliseconds(20))
                guard !Task.isCancelled, let self, state != next else { return }
                commit(next)
            }
        } else {
            commit(next)
        }
    }

    private func commit(_ next: IslandState) {
        state = next
        Self.log.log("state -> \(next.logDescription, privacy: .public)")
        beginMorph()
    }

    /// Returns true when the panel actually had to grow.
    @discardableResult
    private func reserve(_ size: CGSize) -> Bool {
        let target = CGSize(width: max(size.width, containedSize.width),
                            height: max(size.height, containedSize.height))
        guard target != reservation else { return false }
        let grew = target.width > containedSize.width || target.height > containedSize.height
        reservation = target
        onGeometryChange?()
        return grew
    }

    private func beginMorph() {
        isMorphing = true
        onGeometryChange?()

        morphTask?.cancel()
        let settle = reduceMotion
            ? IslandMetrics.reducedMotionDuration
            : IslandMetrics.settleDuration(from: closedSize,
                                           to: IslandMetrics.expandedSize,
                                           spring: IslandMetrics.morphSpring)
        morphTask = Task { [weak self] in
            try? await Task.sleep(for: settle)
            guard !Task.isCancelled, let self else { return }
            isMorphing = false
            // Only now may the panel shrink.
            reservation = nil
            onGeometryChange?()
        }
    }

    /// Escape hatch for display rebuilds: drop to closed with no animation.
    func resetImmediately() {
        hoverTask?.cancel(); morphTask?.cancel()
        hoverTask = nil; morphTask = nil
        isMorphing = false
        reservation = nil
        restingActivity = nil
        state = .closed
        onGeometryChange?()
    }

    /// Snapshot/debug only: seed what the island is showing without animating.
    func restore(activity: Activity?, tint: NSColor) {
        restingActivity = activity
        self.tint = tint
    }

    /// Snapshot/debug only: jump straight to a state with no animation.
    func forceState(_ next: IslandState) {
        state = next
        isMorphing = false
        reservation = nil
    }
}

extension Duration {
    var seconds: Double {
        let (s, attoseconds) = components
        return Double(s) + Double(attoseconds) * 1e-18
    }
}
