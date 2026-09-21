import Foundation

/// A snapshot of whatever is currently playing, normalised from the adapter's
/// JSON. Artwork is carried as encoded bytes, decoded once at the UI edge.
struct NowPlaying: Equatable, Sendable {
    /// Identity of the *track*, used to decide whether artwork can be reused.
    /// The adapter drops artwork for a moment during timeline scrubs.
    var trackID: String?

    var title: String?
    var artist: String?
    var album: String?

    /// Bundle id of the app that owns playback, e.g. `com.apple.Music`.
    var sourceBundleID: String?

    var isPlaying: Bool = false
    var duration: TimeInterval?
    var elapsed: TimeInterval?
    var playbackRate: Double?
    /// When `elapsed` was sampled, so progress can be extrapolated without polling.
    var timestamp: Date?

    var artwork: Data?
    var artworkMIMEType: String?

    var hasContent: Bool { title != nil || artist != nil }
}
