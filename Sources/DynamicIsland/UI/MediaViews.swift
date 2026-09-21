import SwiftUI
import AppKit

/// Resting: artwork in the left extension, waveform (or a play glyph when
/// paused) in the right. The notch itself stays empty, so on a notched Mac the
/// island reads as the notch growing ears rather than as a floating bar.
struct MediaPeekView: View {
    let snapshot: NowPlaying
    let tint: Color
    let notchWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            ArtworkThumb(snapshot: snapshot, tint: tint, side: 20, corner: 5)
                .frame(width: IslandMetrics.peekExtension)

            Spacer(minLength: notchWidth)

            Waveform(isPlaying: snapshot.isPlaying, tint: tint, maxHeight: 13)
                .frame(width: IslandMetrics.peekExtension)
        }
    }
}

/// Hover: a small step up from resting that adds the track title, so the hint
/// carries information rather than just growing.
struct MediaHoverView: View {
    let snapshot: NowPlaying
    let tint: Color
    let notchWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 7) {
                ArtworkThumb(snapshot: snapshot, tint: tint, side: 26, corner: 6)
                Text(snapshot.title ?? "")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(width: IslandMetrics.hoverExtension + notchWidth / 2 - 6, alignment: .leading)
            .padding(.leading, 10)

            Spacer(minLength: 0)

            Waveform(isPlaying: snapshot.isPlaying, tint: tint, maxHeight: 15)
                .padding(.trailing, 14)
        }
    }
}

/// The full player, opened by a click.
///
/// Three rows, matching the reference: artwork and track on top, a full-width
/// progress bar under them, then transport. Dimensions are measured from the
/// reference rather than guessed -- island 373x174, artwork 56.
struct MediaExpandedView: View {
    let snapshot: NowPlaying
    let tint: Color
    let onCommand: (MediaRemoteHelper.Command) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 13) {
                ArtworkThumb(snapshot: snapshot, tint: tint, side: 56, corner: 11)
                    .shadow(color: tint.opacity(0.45), radius: 10, y: 3)

                VStack(alignment: .leading, spacing: 3) {
                    Text(snapshot.title ?? "Nothing playing")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(snapshot.artist ?? "")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                .padding(.top, 1)

                Spacer(minLength: 6)

                Waveform(isPlaying: snapshot.isPlaying, tint: tint,
                         barCount: 5, barWidth: 2, maxHeight: 13)
                    .padding(.top, 3)
            }
            .frame(height: 56)

            PlaybackProgress(snapshot: snapshot, tint: tint)
                .padding(.top, 17)

            HStack(spacing: 0) {
                control("shuffle", .toggleShuffle, active: snapshot.isShuffling)
                Spacer(minLength: 0)
                control("backward.fill", .previousTrack)
                Spacer(minLength: 0)
                control(snapshot.isPlaying ? "pause.fill" : "play.fill",
                        .togglePlayPause, size: 18)
                Spacer(minLength: 0)
                control("forward.fill", .nextTrack)
                Spacer(minLength: 0)
                outputDevice
            }
            .padding(.horizontal, 4)
            .padding(.top, 15)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 16)
        // Clicking the body closes the player. SwiftUI gives the buttons
        // priority over an ancestor's tap gesture, so the controls still win.
        .contentShape(Rectangle())
        .onTapGesture { onDismiss() }
    }

    /// Reflects the real default output device, and opens Sound settings.
    /// Read at render time rather than observed: the player is only on screen
    /// while the user is looking at it.
    private var outputDevice: some View {
        let device = AudioOutput.current()
        return Button {
            if let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") {
                NSWorkspace.shared.open(url)
            }
        } label: {
            Image(systemName: device.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .frame(width: 30, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(device.name)
    }

    private func control(_ symbol: String, _ command: MediaRemoteHelper.Command,
                         size: CGFloat = 13, active: Bool = false) -> some View {
        Button {
            onCommand(command)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(active ? tint : .white.opacity(0.92))
                .frame(width: 30, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Elapsed position with both times, as in the reference. Extrapolated from the
/// last sample and the playback rate rather than polled, so a paused island
/// schedules nothing.
struct PlaybackProgress: View {
    let snapshot: NowPlaying
    let tint: Color

    var body: some View {
        if snapshot.isPlaying, (snapshot.duration ?? 0) > 0 {
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                content(at: context.date)
            }
        } else {
            content(at: .now)
        }
    }

    private func content(at date: Date) -> some View {
        let elapsed = elapsed(at: date)
        let duration = snapshot.duration ?? 0
        let fraction = duration > 0 ? min(max(elapsed / duration, 0), 1) : 0

        return VStack(spacing: 5) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.16))
                    Capsule().fill(tint).frame(width: max(2, geo.size.width * fraction))
                }
            }
            .frame(height: 3)

            HStack {
                Text(Self.clock(elapsed))
                Spacer(minLength: 0)
                Text("-" + Self.clock(max(0, duration - elapsed)))
            }
            .font(.system(size: 9.5, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.5))
        }
    }

    private func elapsed(at date: Date) -> TimeInterval {
        var elapsed = snapshot.elapsed ?? 0
        if snapshot.isPlaying, let sampled = snapshot.timestamp {
            elapsed += date.timeIntervalSince(sampled) * (snapshot.playbackRate ?? 1)
        }
        return max(0, elapsed)
    }

    private static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
