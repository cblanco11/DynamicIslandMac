import SwiftUI

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
struct MediaExpandedView: View {
    let snapshot: NowPlaying
    let tint: Color
    let onCommand: (MediaRemoteHelper.Command) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 13) {
                ArtworkThumb(snapshot: snapshot, tint: tint, side: 74, corner: 14)
                    .shadow(color: tint.opacity(0.5), radius: 12, y: 4)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .top, spacing: 8) {
                        Text(snapshot.title ?? "Nothing playing")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Spacer(minLength: 0)

                        Waveform(isPlaying: snapshot.isPlaying, tint: tint,
                                 barCount: 5, barWidth: 2, maxHeight: 13)
                            .padding(.top, 2)
                    }

                    Text(snapshot.artist ?? "")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    PlaybackProgress(snapshot: snapshot, tint: tint)
                }
                .frame(height: 74)
            }

            HStack(spacing: 0) {
                control("shuffle", .toggleShuffle, active: snapshot.isShuffling)
                Spacer(minLength: 0)
                control("backward.fill", .previousTrack)
                Spacer(minLength: 0)
                control(snapshot.isPlaying ? "pause.fill" : "play.fill",
                        .togglePlayPause, size: 19)
                Spacer(minLength: 0)
                control("forward.fill", .nextTrack)
                Spacer(minLength: 0)
                control("repeat", .toggleRepeat, active: snapshot.isRepeating)
            }
            .padding(.horizontal, 8)
            .padding(.top, 12)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, 15)
        .padding(.bottom, 12)
        // Clicking the body closes the player. SwiftUI gives the buttons
        // priority over an ancestor's tap gesture, so the controls still win.
        .contentShape(Rectangle())
        .onTapGesture { onDismiss() }
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

        return VStack(spacing: 4) {
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
