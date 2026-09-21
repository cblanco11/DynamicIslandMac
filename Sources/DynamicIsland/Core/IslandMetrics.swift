import Foundation

/// Every tunable number in one place. Hover delays are overridable via
/// `UserDefaults` so timing can be dialled in without a rebuild.
enum IslandMetrics {
    /// The panel is sized to this once and never resized; the island is drawn
    /// inside it. Generous enough to hold Milestone 2-4 content.
    static let panelSize = CGSize(width: 640, height: 220)

    static let expandedSize = CGSize(width: 380, height: 120)

    static var hoverInDelay: Duration {
        .milliseconds(UserDefaults.standard.object(forKey: "DIHoverInDelayMS") as? Int ?? 120)
    }

    static var hoverOutDelay: Duration {
        .milliseconds(UserDefaults.standard.object(forKey: "DIHoverOutDelayMS") as? Int ?? 350)
    }

    /// How long the morph runs. Used both for the spring and to know when the
    /// widened hit region can safely shrink back.
    static let morphDuration: Duration = .milliseconds(420)
    static let reducedMotionDuration: Duration = .milliseconds(80)
}
