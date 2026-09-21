import Foundation
import Observation
import os

/// Merges every provider's snapshot and decides what the island shows.
///
/// Ranking is priority first, then recency. Ties on both are broken by provider
/// registration order so the result is stable rather than arbitrary.
@MainActor
@Observable
final class ActivityRegistry {

    private(set) var activities: [Activity] = []

    /// Fired whenever the top activity changes. A callback rather than
    /// observation plumbing because the consumer is AppKit.
    var onChange: (@MainActor (Activity?) -> Void)?

    /// What the island should currently present, or nil for nothing.
    var top: Activity? { activities.first }

    @ObservationIgnored private var providers: [(provider: any ActivityProvider, order: Int)] = []
    @ObservationIgnored private var snapshots: [String: [Activity]] = [:]
    @ObservationIgnored private var pumps: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var sweeper: Task<Void, Never>?
    @ObservationIgnored private static let log =
        Logger(subsystem: "com.jeffreyotoo.DynamicIsland", category: "activities")

    func register(_ provider: any ActivityProvider) {
        let id = provider.providerID
        guard pumps[id] == nil else { return }
        providers.append((provider, providers.count))

        let stream = provider.start()
        pumps[id] = Task { [weak self] in
            for await snapshot in stream {
                guard let self else { return }
                snapshots[id] = snapshot
                recompute()
            }
            self?.snapshots[id] = nil
            self?.recompute()
        }
        Self.log.notice("registered provider \(id, privacy: .public)")
    }

    func stopAll() {
        for (provider, _) in providers { provider.stop() }
        for (_, pump) in pumps { pump.cancel() }
        pumps.removeAll()
        providers.removeAll()
        snapshots.removeAll()
        sweeper?.cancel()
        sweeper = nil
        activities = []
    }

    private func recompute() {
        let order = Dictionary(uniqueKeysWithValues: providers.map { ($0.provider.providerID, $0.order) })
        let merged = snapshots
            .flatMap { id, list in list.map { (activity: $0, order: order[id] ?? .max) } }
            .sorted { a, b in
                if a.activity.priority != b.activity.priority {
                    return a.activity.priority > b.activity.priority
                }
                if a.activity.updatedAt != b.activity.updatedAt {
                    return a.activity.updatedAt > b.activity.updatedAt
                }
                return a.order < b.order
            }
            .map(\.activity)

        guard merged != activities else { return }
        let previousTop = activities.first
        activities = merged
        if merged.first != previousTop { onChange?(merged.first) }
        scheduleSweep()
    }

    /// Auto-dismissing activities need a wake-up, but only while one is actually
    /// present -- an idle island must have nothing scheduled.
    private func scheduleSweep() {
        sweeper?.cancel()
        sweeper = nil

        let deadlines = activities.compactMap { activity -> Duration? in
            guard let window = activity.autoDismissAfter else { return nil }
            let elapsed = Duration.seconds(Date.now.timeIntervalSince(activity.updatedAt))
            return window > elapsed ? window - elapsed : .zero
        }
        guard let next = deadlines.min() else { return }

        sweeper = Task { [weak self] in
            try? await Task.sleep(for: next == .zero ? .milliseconds(1) : next)
            guard !Task.isCancelled, let self else { return }
            let now = Date.now
            for (id, list) in snapshots {
                let kept = list.filter { activity in
                    guard let window = activity.autoDismissAfter else { return true }
                    return Duration.seconds(now.timeIntervalSince(activity.updatedAt)) < window
                }
                if kept.count != list.count { snapshots[id] = kept }
            }
            recompute()
        }
    }
}
