import AppKit

/// Where the notch is on a given screen, in global (Y-up) screen coordinates.
struct NotchGeometry: Equatable, Sendable {
    var rect: CGRect
    /// True when the screen has no real notch and we invented one.
    var isSynthetic: Bool
}

@MainActor
enum ScreenGeometry {
    /// Matches the built-in 14"/16" MacBook Pro notch (measured: 185 x 32 pt on Mac15,6).
    static let syntheticNotchSize = CGSize(width: 185, height: 32)

    /// Debug default: pretend every screen is notchless, to exercise the
    /// synthetic path without physically attaching an external display.
    static var forceSynthetic: Bool {
        UserDefaults.standard.bool(forKey: "DIForceSyntheticNotch")
    }

    /// `auxiliaryTopLeftArea` returns nil whenever the menu bar is hidden or
    /// auto-hidden. Without a cache, a probe taken at such a moment would
    /// silently demote a real notch to a synthetic one, so remember the last
    /// good answer per display.
    private static var lastKnownGood: [CGDirectDisplayID: CGRect] = [:]

    static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    static func notch(for screen: NSScreen) -> NotchGeometry {
        if forceSynthetic { return synthetic(for: screen) }

        let id = displayID(for: screen)

        if let measured = measure(screen) {
            if let id { lastKnownGood[id] = measured }
            return NotchGeometry(rect: measured, isSynthetic: false)
        }
        if let id, let cached = lastKnownGood[id] {
            return NotchGeometry(rect: cached, isSynthetic: false)
        }
        return synthetic(for: screen)
    }

    /// Derive the true notch rect from the two auxiliary top areas.
    private static func measure(_ screen: NSScreen) -> CGRect? {
        let inset = screen.safeAreaInsets.top
        guard inset > 0,
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea
        else { return nil }

        // Widths are coordinate-space independent, so the notch width is always
        // safe to derive this way even if the rects' origins surprise us.
        let width = screen.frame.width - left.width - right.width
        guard width > 0 else { return nil }

        // The X origin is not: AppKit documents these rects as being in "the
        // screen's coordinate space", which is ambiguous for a secondary
        // display. Detect which interpretation we got instead of assuming.
        let originX: CGFloat
        if abs(left.minX - screen.frame.minX) < 1 {
            originX = left.maxX                             // global coordinates
        } else if abs(left.minX) < 1 {
            originX = screen.frame.minX + left.width        // screen-local
        } else {
            originX = screen.frame.midX - width / 2         // neither: centre it
        }

        return CGRect(x: originX,
                      y: screen.frame.maxY - inset,
                      width: width,
                      height: inset)
    }

    private static func synthetic(for screen: NSScreen) -> NotchGeometry {
        let size = syntheticNotchSize
        return NotchGeometry(
            rect: CGRect(x: screen.frame.midX - size.width / 2,
                         y: screen.frame.maxY - size.height,
                         width: size.width,
                         height: size.height),
            isSynthetic: true
        )
    }

    /// Drop cached probes for displays that are no longer attached.
    static func pruneCache(keeping screens: [NSScreen]) {
        let live = Set(screens.compactMap(displayID(for:)))
        lastKnownGood = lastKnownGood.filter { live.contains($0.key) }
    }
}
