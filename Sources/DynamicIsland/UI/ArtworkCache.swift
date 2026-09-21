import AppKit

/// Decodes artwork once per track.
///
/// Snapshots arrive several times a second while playback advances and each
/// carries the full ~140KB JPEG; decoding on every render would burn CPU for no
/// visible change. Keyed by track, holding only the current one and the one
/// before it so a track change does not flash.
@MainActor
enum ArtworkCache {
    private static var entries: [(id: String, image: NSImage)] = []

    static func image(for snapshot: NowPlaying) -> NSImage? {
        guard let id = snapshot.trackID else {
            return snapshot.artwork.flatMap(NSImage.init(data:))
        }
        if let hit = entries.first(where: { $0.id == id }) { return hit.image }
        guard let data = snapshot.artwork, let image = NSImage(data: data) else { return nil }
        entries.insert((id, image), at: 0)
        if entries.count > 2 { entries.removeLast() }
        return image
    }
}
