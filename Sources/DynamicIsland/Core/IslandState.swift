import Foundation

/// A unit of content the island can surface.
///
/// Milestone 1 ships the shell only, so this is a deliberately minimal
/// placeholder. The real `ActivityProvider` protocol is designed in Milestone 4,
/// *before* any provider (media included) is written against it.
struct Activity: Equatable, Identifiable, Sendable {
    let id: String
    var title: String
}

/// The island's explicit state machine. Views are pure functions of this.
enum IslandState: Equatable, Sendable {
    case closed
    case peek(Activity)
    case expanded

    var isClosed: Bool { self == .closed }
}
