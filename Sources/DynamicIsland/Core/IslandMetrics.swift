import SwiftUI

/// Every tunable number in one place. Hover delays are overridable via
/// `UserDefaults` so timing can be dialled in without a rebuild.
enum IslandMetrics {
    static let expandedSize = CGSize(width: 356, height: 174)

    /// Hover is a hint, not a reveal: a small step up from the resting pill so
    /// it reads as clickable without committing the screen space.
    ///
    /// Tall enough to carry a title row *below* the notch. Anything drawn in the
    /// notch's x-range above `notch.height` is behind the physical camera
    /// housing and simply cannot be seen.
    static let hoverExtension: CGFloat = 68
    static let hoverHeight: CGFloat = 62

    /// Progress bar thickness. Measured from the reference.
    static let progressBarHeight: CGFloat = 6

    /// How far the peek pill extends past the notch on each side. Artwork sits
    /// in the left extension, the playing indicator in the right -- the notch
    /// itself stays visually untouched.
    static let peekExtension: CGFloat = 46

    /// The concave top corners flare this far outside the island's own rect, so
    /// the panel needs this much margin on each side or they get clipped.
    static let shoulderRadius: CGFloat = 12

    /// Extra panel height claimed while the debug overlay is visible.
    static let debugOverlayHeight: CGFloat = 96

    static var hoverInDelay: Duration {
        .milliseconds(UserDefaults.standard.object(forKey: "DIHoverInDelayMS") as? Int ?? 120)
    }

    static var hoverOutDelay: Duration {
        .milliseconds(UserDefaults.standard.object(forKey: "DIHoverOutDelayMS") as? Int ?? 350)
    }

    // MARK: - Morph

    /// The morph spring. Tunable at runtime so the feel can be dialled in
    /// without a rebuild:
    ///
    ///     defaults write com.jeffreyotoo.DynamicIsland DIMorphDuration -float 0.45
    ///     defaults write com.jeffreyotoo.DynamicIsland DIMorphBounce   -float 0.30
    ///
    /// Bounce matters more than it looks: the island's sideways growth happens
    /// against the dark menu bar, where black-on-dark-grey is nearly invisible,
    /// while its downward growth appears over bright wallpaper. Without
    /// overshoot the only high-contrast motion is downward, so a symmetric
    /// expansion still reads as "dropping out of the notch". Overshoot puts
    /// visible motion at the left and right edges.
    static var morphSpring: Spring {
        let defaults = UserDefaults.standard
        let duration = defaults.object(forKey: "DIMorphDuration") as? Double ?? 0.45
        let bounce = defaults.object(forKey: "DIMorphBounce") as? Double ?? 0.30
        return Spring(duration: duration, bounce: bounce)
    }

    /// When the spring has actually settled, derived from the spring rather than
    /// hardcoded -- the panel must not shrink back before the shape has finished
    /// collapsing, or the island gets clipped mid-morph.
    static func settleDuration(from: CGSize, to: CGSize, spring: Spring) -> Duration {
        var t = 0.0
        let limit = 4.0
        while t < limit {
            let w = spring.value(fromValue: from.width, toValue: to.width, initialVelocity: 0, time: t)
            let h = spring.value(fromValue: from.height, toValue: to.height, initialVelocity: 0, time: t)
            if abs(w - to.width) < 0.5 && abs(h - to.height) < 0.5 {
                // A little slack so the panel never leads the shape.
                return .milliseconds(Int(t * 1000) + 60)
            }
            t += 1.0 / 120.0
        }
        return .milliseconds(Int(limit * 1000))
    }

    static let reducedMotionDuration: Duration = .milliseconds(80)
}
