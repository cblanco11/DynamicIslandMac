import AppKit
import os

/// Publishes whatever is playing as an `Activity`.
///
/// Media is `.ambient`: it is always there when something is playing, and any
/// deliberate activity -- a script push, a volume keypress -- outranks it.
@MainActor
final class MediaActivityProvider: ActivityProvider {

    nonisolated let providerID = "media"

    private let helper = MediaRemoteHelper()
    private var pump: Task<Void, Never>?
    private let log = Logger(subsystem: "com.jeffreyotoo.DynamicIsland", category: "media")

    /// Decoding artwork and scoring its colour is the expensive part, so it is
    /// done once per track rather than once per snapshot -- and snapshots arrive
    /// several times a second while scrubbing.
    private var tintCache: (trackID: String, color: NSColor)?

    func start() -> AsyncStream<[Activity]> {
        AsyncStream { continuation in
            pump = Task { [weak self] in
                guard let self else { return }
                for await snapshot in helper.start() {
                    continuation.yield(self.activities(for: snapshot))
                }
                continuation.finish()
            }
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.stop() }
            }
        }
    }

    func stop() {
        pump?.cancel()
        pump = nil
        helper.stop()
    }

    func send(_ command: MediaRemoteHelper.Command) {
        helper.send(command)
    }

    /// The tint for the current track, computed lazily and cached.
    func tint(for snapshot: NowPlaying) -> NSColor {
        guard let id = snapshot.trackID else { return ArtworkColor.fallback }
        if let cached = tintCache, cached.trackID == id { return cached.color }
        guard let artwork = snapshot.artwork else { return ArtworkColor.fallback }
        let color = ArtworkColor.dominant(in: artwork)
        tintCache = (id, color)
        return color
    }

    private func activities(for snapshot: NowPlaying) -> [Activity] {
        guard snapshot.hasContent else { return [] }
        return [Activity(id: providerID,
                         priority: .ambient,
                         kind: .nowPlaying(snapshot),
                         updatedAt: .now)]
    }
}
