import Foundation

/// Every tunable number in one place. Hover delays are overridable via
/// `UserDefaults` so timing can be dialled in without a rebuild.
enum IslandMetrics {
    static let expandedSize = CGSize(width: 380, height: 120)

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

    /// How long the morph runs. Used both for the spring and to know when the
    /// panel may safely shrink back.
    static let morphDuration: Duration = .milliseconds(420)
    static let reducedMotionDuration: Duration = .milliseconds(80)
}
