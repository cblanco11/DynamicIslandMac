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

/// Hover: a small step up from resting that adds the track title.
///
/// The top strip mirrors the resting pill -- artwork and waveform sit in the
/// extensions either side of the notch -- and the title goes on a second row
/// **below** the notch. Text in the notch's x-range above `notch.height` is
/// behind the camera housing and invisible, so it cannot live up there.
struct MediaHoverView: View {
    let snapshot: NowPlaying
    let tint: Color
    let notchWidth: CGFloat
    let notchHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ArtworkThumb(snapshot: snapshot, tint: tint, side: 22, corner: 5)
                    .frame(width: IslandMetrics.hoverExtension)

                Spacer(minLength: notchWidth)

                Waveform(isPlaying: snapshot.isPlaying, tint: tint, maxHeight: 14)
                    .frame(width: IslandMetrics.hoverExtension)
            }
            .frame(height: notchHeight)

            Text(snapshot.title ?? "")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    let notchHeight: CGFloat
    let onCommand: (MediaRemoteHelper.Command) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 13) {
                // Sits left of the notch, so it may start at the very top.
                ArtworkThumb(snapshot: snapshot, tint: tint, side: 56, corner: 11)
                    .shadow(color: tint.opacity(0.45), radius: 10, y: 3)

                // Bottom-aligned inside the artwork's row. The title's x-range
                // overlaps the notch, so it has to clear `notchHeight`; pushing
                // it to the bottom of a 56pt row puts it at ~44pt, which does.
                VStack(alignment: .leading, spacing: 2) {
                    Spacer(minLength: 0)

                    Text(snapshot.title ?? "Nothing playing")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(snapshot.artist ?? "")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                .frame(height: 56)

                Spacer(minLength: 6)

                // Clear of the notch on the right, so it can sit high.
                // Scaled with the transport controls, or it reads as undersized
                // next to them.
                Waveform(isPlaying: snapshot.isPlaying, tint: tint,
                         barCount: 5, barWidth: 2.5, maxHeight: 16)
                    .padding(.top, 2)
            }
            .frame(height: 56)

            PlaybackProgress(snapshot: snapshot, tint: tint)
                .padding(.top, 16)

            HStack(spacing: 0) {
                control("shuffle", .toggleShuffle, active: snapshot.isShuffling)
                Spacer(minLength: 0)
                control("backward.fill", .previousTrack)
                Spacer(minLength: 0)
                control(snapshot.isPlaying ? "pause.fill" : "play.fill",
                        .togglePlayPause, size: Self.playSymbolSize)
                Spacer(minLength: 0)
                control("forward.fill", .nextTrack)
                Spacer(minLength: 0)
                outputDevice
            }
            // Button centres sit ~56pt in from each island edge, as measured
            // from the reference. The larger hit frames then close the gaps
            // between glyphs to ~40pt, a little tighter than the reference's 43.
            .padding(.horizontal, 8)
            .padding(.top, 8)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 14)
        // Clicking the body closes the player. SwiftUI gives the buttons
        // priority over an ancestor's tap gesture, so the controls still win.
        .contentShape(Rectangle())
        .onTapGesture { onDismiss() }
    }

    /// Sized from the reference: side glyphs render ~24x14pt, the play/pause
    /// glyph ~17x23pt. SF Symbols at these point sizes land within a point of
    /// that; the hit frame is deliberately larger than the glyph so the
    /// controls stay comfortable to click.
    private static let symbolSize: CGFloat = 17.5
    private static let playSymbolSize: CGFloat = 24
    private static let hitFrame = CGSize(width: 38, height: 30)

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
                .font(.system(size: Self.symbolSize, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .frame(width: Self.hitFrame.width, height: Self.hitFrame.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(device.name)
    }

    private func control(_ symbol: String, _ command: MediaRemoteHelper.Command,
                         size: CGFloat = symbolSize, active: Bool = false) -> some View {
        Button {
            onCommand(command)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(active ? tint : .white.opacity(0.92))
                .frame(width: Self.hitFrame.width, height: Self.hitFrame.height)
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
                    Capsule().fill(tint)
                        .frame(width: max(IslandMetrics.progressBarHeight,
                                          geo.size.width * fraction))
                }
            }
            .frame(height: IslandMetrics.progressBarHeight)

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
