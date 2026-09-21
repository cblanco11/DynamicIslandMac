import Foundation

/// The island's explicit state machine. Views are pure functions of this.
///
/// `.peek` carries the activity so the view never has to reach back into the
/// registry to find out what it is drawing.
enum IslandState: Equatable, Sendable {
    /// Nothing to show: the island is exactly the notch.
    case closed
    /// Resting with something to show.
    case peek(Activity)
    /// Cursor is over the island. A small growth, purely an affordance that
    /// says "this is clickable" -- the full player is a deliberate click.
    case hover(Activity)
    /// Opened by a click.
    case expanded

    var isClosed: Bool { self == .closed }

    var activity: Activity? {
        switch self {
        case .peek(let a), .hover(let a): a
        case .closed, .expanded:          nil
        }
    }

    var isExpanded: Bool { self == .expanded }

    /// Short form for logging. The default reflection dump includes the whole
    /// activity payload, artwork byte counts and all.
    var logDescription: String {
        switch self {
        case .closed:            "closed"
        case .peek(let a):       "peek(\(a.id))"
        case .hover(let a):      "hover(\(a.id))"
        case .expanded:          "expanded"
        }
    }
}
