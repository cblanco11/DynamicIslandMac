import Foundation

/// A source of activities for the island.
///
/// Providers own their own lifecycle and push whole snapshots rather than
/// deltas: each element is the complete set of activities that provider
/// currently has. That keeps the registry's merge trivial and means a provider
/// that crashes and restarts cannot leak stale entries -- its next snapshot
/// simply replaces everything it had.
///
/// Media is one implementation of this, not a special case.
@MainActor
protocol ActivityProvider: AnyObject {
    /// Stable identity, e.g. `"media"`. Used for logging and to scope the
    /// provider's activities within the registry.
    nonisolated var providerID: String { get }

    /// Begin producing. The stream finishes when the provider stops.
    func start() -> AsyncStream<[Activity]>

    /// Stop producing and release any resources (child processes, observers).
    func stop()
}
