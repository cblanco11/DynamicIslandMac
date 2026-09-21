import Foundation

/// The island's explicit state machine. Views are pure functions of this.
///
/// `.peek` carries the activity so the view never has to reach back into the
/// registry to find out what it is drawing.
enum IslandState: Equatable, Sendable {
    case closed
    case peek(Activity)
    case expanded

    var isClosed: Bool { self == .closed }

    var activity: Activity? {
        if case .peek(let activity) = self { return activity }
        return nil
    }
}
