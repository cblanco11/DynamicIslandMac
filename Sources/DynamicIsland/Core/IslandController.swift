import AppKit
import SwiftUI
import Observation
import os

/// Owns the island's state machine and hover timing for a single screen.
/// Views read it; nothing else mutates it.
@MainActor
@Observable
final class IslandController {

    private(set) var state: IslandState = .closed
    private(set) var notch: NotchGeometry

    /// True from the moment a morph starts until it has settled. Keeps the hit
    /// region wide mid-flight.
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

    /// Fired whenever `interactiveFrame` or the overlay state changes, so the
    /// container can resize its tracking area and start/stop the display link.
    /// An explicit callback rather than observation plumbing: this crosses into
    /// AppKit, where a re-arming `withObservationTracking` loop is more machinery
    /// than the one signal warrants.
    var onGeometryChange: (@MainActor () -> Void)?

    @ObservationIgnored private static let log =
        Logger(subsystem: "com.jeffreyotoo.DynamicIsland", category: "state")

    @ObservationIgnored private var hoverTask: Task<Void, Never>?
    @ObservationIgnored private var morphTask: Task<Void, Never>?
    @ObservationIgnored private var reduceMotionObserver: NSObjectProtocol?

    init(notch: NotchGeometry) {
        self.notch = notch
        // Read live, not once at launch -- the user can flip this while we run.
        reduceMotionObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            }
        }
    }

    /// Explicit teardown rather than `deinit`: a nonisolated `deinit` cannot
    /// touch MainActor-isolated, non-Sendable state under Swift 6. `PanelManager`
    /// is the sole owner of controllers and calls this when a display departs.
    func tearDown() {
        hoverTask?.cancel()
        morphTask?.cancel()
        hoverTask = nil
        morphTask = nil
        onGeometryChange = nil
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

    /// The island's own size in the current state.
    var currentSize: CGSize {
        switch state {
        case .closed:           closedSize
        case .peek, .expanded:  IslandMetrics.expandedSize
        }
    }

    /// The island size the panel must be able to contain right now. While a
    /// morph is in flight this is the larger of source and target, so the panel
    /// is already big enough before the shape grows into it, and only shrinks
    /// once the shape has finished collapsing.
    private var containedSize: CGSize {
        guard isMorphing else { return currentSize }
        return CGSize(width: max(currentSize.width, IslandMetrics.expandedSize.width),
                      height: max(currentSize.height, IslandMetrics.expandedSize.height))
    }

    /// The panel's size. The panel frame *is* the interactive region: the window
    /// server routes clicks by frame, so anything the panel covers is a click the
    /// app underneath does not get. See CLAUDE.md, "hitTest does not produce
    /// click pass-through".
    var panelSize: CGSize {
        let island = containedSize
        return CGSize(
            width: island.width + 2 * IslandMetrics.shoulderRadius,
            height: island.height + (debugOverlayEnabled ? IslandMetrics.debugOverlayHeight : 0)
        )
    }

    /// The island's frame inside the panel: horizontally centred, pinned to the
    /// top edge. Top-left origin, matching the flipped container view.
    var islandFrame: CGRect {
        let size = currentSize
        return CGRect(x: (panelSize.width - size.width) / 2, y: 0,
                      width: size.width, height: size.height)
    }

    /// What the tracking area covers. The union of source and target while
    /// morphing: if this shrank the moment a collapse began, a fast hover-out
    /// would fall through the gap and strand the island open.
    var interactiveFrame: CGRect {
        let resting = islandFrame
        guard isMorphing else { return resting }
        let expanded = CGRect(x: (panelSize.width - IslandMetrics.expandedSize.width) / 2, y: 0,
                              width: IslandMetrics.expandedSize.width,
                              height: IslandMetrics.expandedSize.height)
        return resting.union(expanded)
    }

    // MARK: - Animation

    var animation: Animation {
        reduceMotion
            ? .easeOut(duration: IslandMetrics.reducedMotionDuration.seconds)
            : .spring(IslandMetrics.morphSpring)
    }

    // MARK: - Hover

    func mouseEntered() {
        scheduleHover(after: IslandMetrics.hoverInDelay) { controller in
            controller.transition(to: .expanded)
        }
    }

    func mouseExited() {
        scheduleHover(after: IslandMetrics.hoverOutDelay) { controller in
            controller.transition(to: .closed)
        }
    }

    /// Cancels any pending hover intent and replaces it. One `Task` at a time and
    /// no repeating timer -- an idle app must have nothing scheduled at all.
    private func scheduleHover(after delay: Duration,
                               _ body: @escaping @MainActor (IslandController) -> Void) {
        hoverTask?.cancel()
        hoverTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            body(self)
        }
    }

    private func transition(to next: IslandState) {
        guard next != state else { return }
        state = next
        // .default rather than .info so the transition is persisted and
        // `log show` can confirm the hover machine actually fired.
        Self.log.log("state -> \(String(describing: next), privacy: .public)")
        beginMorph()
    }

    private func beginMorph() {
        isMorphing = true
        onGeometryChange?()

        morphTask?.cancel()
        // Derived from the live spring, so retuning the curve cannot leave the
        // panel shrinking before the shape has finished collapsing.
        let settle = reduceMotion
            ? IslandMetrics.reducedMotionDuration
            : IslandMetrics.settleDuration(from: closedSize,
                                           to: IslandMetrics.expandedSize,
                                           spring: IslandMetrics.morphSpring)
        morphTask = Task { [weak self] in
            try? await Task.sleep(for: settle)
            guard !Task.isCancelled, let self else { return }
            isMorphing = false
            onGeometryChange?()
        }
    }

    /// Snapshot/debug only: jump straight to a state with no animation.
    func forceState(_ next: IslandState) {
        state = next
        isMorphing = false
    }

    /// Escape hatch for display rebuilds: drop to closed with no animation.
    func resetImmediately() {
        hoverTask?.cancel()
        morphTask?.cancel()
        hoverTask = nil
        morphTask = nil
        isMorphing = false
        state = .closed
        onGeometryChange?()
    }
}

extension Duration {
    var seconds: Double {
        let (s, attoseconds) = components
        return Double(s) + Double(attoseconds) * 1e-18
    }
}
