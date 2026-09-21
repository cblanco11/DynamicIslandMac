import Foundation

/// How an activity ranks against others competing for the island.
///
/// Deliberately coarse. Fine-grained ordering within a band is by recency, which
/// is what people actually expect: the thing that just happened wins.
enum ActivityPriority: Int, Comparable, Sendable {
    /// Always-available background state. Media lives here.
    case ambient = 0
    /// Something a script or the user explicitly started.
    case normal = 500
    /// A direct response to a keypress the user just made. HUD lives here.
    case immediate = 1000

    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

/// What the island is being asked to show.
///
/// A closed enum rather than provider-supplied views, so that island views stay
/// pure functions of state and the renderer stays exhaustive. Providers describe
/// *what* they have; the island decides how it looks.
enum ActivityKind: Equatable, Sendable {
    /// Something is playing. Milestone 2.
    case nowPlaying(NowPlaying)

    /// A titled, optionally-measured piece of work. This is what the `island`
    /// CLI pushes, and the shape most third-party activities collapse to.
    case task(TaskActivity)

    /// A momentary scalar readout: volume, brightness. Milestone 3.
    case level(LevelActivity)
}

/// One thing the island can show, from one provider.
struct Activity: Identifiable, Equatable, Sendable {
    /// Stable for the lifetime of the activity, so updates replace rather than
    /// stack. `"media"` for the media provider; the `--id` for CLI pushes.
    let id: String
    var priority: ActivityPriority
    var kind: ActivityKind
    /// When this activity last changed, used to break priority ties.
    var updatedAt: Date = .now
    /// Dismiss itself after this long without an update. Nil means it persists
    /// until its provider withdraws it.
    var autoDismissAfter: Duration?
}

/// A titled unit of work, measured or not.
struct TaskActivity: Equatable, Sendable {
    var title: String
    var subtitle: String?
    /// 0...1, or nil for indeterminate.
    var progress: Double?
    var state: State

    enum State: String, Equatable, Sendable {
        case active, success, failure, cancelled
    }
}

/// A scalar the user is actively changing.
struct LevelActivity: Equatable, Sendable {
    var kind: Kind
    /// 0...1
    var value: Double
    var isMuted: Bool

    enum Kind: String, Equatable, Sendable {
        case volume, brightness, keyboardBrightness
    }
}
