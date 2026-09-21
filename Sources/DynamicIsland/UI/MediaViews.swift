import SwiftUI

/// The compact presentation: artwork in the left extension, a playing indicator
/// in the right. The notch itself stays empty, so on a notched Mac the island
/// reads as the notch growing ears rather than as a floating bar.
struct MediaPeekView: View {
    let snapshot: NowPlaying
    let tint: Color
    let notchWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            artwork
                .frame(width: IslandMetrics.peekExtension, height: IslandMetrics.peekExtension)

            Spacer(minLength: notchWidth)

            PlayingIndicator(isPlaying: snapshot.isPlaying, tint: tint)
                .frame(width: IslandMetrics.peekExtension, height: IslandMetrics.peekExtension)
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if let image = ArtworkCache.image(for: snapshot) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 20, height: 20)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(tint.opacity(0.35))
                .frame(width: 20, height: 20)
                .overlay(Image(systemName: "music.note")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8)))
        }
    }
}

/// Three bars that breathe while playing and rest flat when paused.
///
/// Driven by `TimelineView`, so it stops scheduling work the moment playback
/// pauses -- an idle island must not be running an animation.
struct PlayingIndicator: View {
    let isPlaying: Bool
    let tint: Color

    var body: some View {
        if isPlaying {
            TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { context in
                bars(at: context.date.timeIntervalSinceReferenceDate)
            }
        } else {
            bars(at: nil)
        }
    }

    private func bars(at time: TimeInterval?) -> some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(0..<3, id: \.self) { i in
                let phase = (time ?? 0) * 3.4 + Double(i) * 1.1
                let height: CGFloat = time == nil ? 4 : 4 + 9 * (0.5 + 0.5 * sin(phase))
                Capsule()
                    .fill(tint)
                    .frame(width: 2.5, height: height)
            }
        }
        .frame(height: 16)
    }
}

/// The full presentation: artwork, what is playing, where it is up to, and
/// transport.
struct MediaExpandedView: View {
    let snapshot: NowPlaying
    let tint: Color
    let onCommand: (MediaRemoteHelper.Command) -> Void

    var body: some View {
        HStack(spacing: 12) {
            artwork

            VStack(alignment: .leading, spacing: 3) {
                Text(snapshot.title ?? "Nothing playing")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(snapshot.artist ?? "")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)

                PlaybackProgress(snapshot: snapshot, tint: tint)
                    .padding(.top, 2)

                HStack(spacing: 18) {
                    transport("backward.fill", .previousTrack)
                    transport(snapshot.isPlaying ? "pause.fill" : "play.fill", .togglePlayPause, large: true)
                    transport("forward.fill", .nextTrack)
                }
                .padding(.top, 3)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var artwork: some View {
        Group {
            if let image = ArtworkCache.image(for: snapshot) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                tint.opacity(0.35).overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8)))
            }
        }
        .frame(width: 68, height: 68)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: tint.opacity(0.45), radius: 10, y: 3)
    }

    private func transport(_ symbol: String, _ command: MediaRemoteHelper.Command,
                           large: Bool = false) -> some View {
        Button {
            onCommand(command)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: large ? 15 : 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: large ? 22 : 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Elapsed position. Extrapolated from the last sample and the playback rate
/// rather than polled, so a paused island schedules nothing.
struct PlaybackProgress: View {
    let snapshot: NowPlaying
    let tint: Color

    var body: some View {
        if snapshot.isPlaying, snapshot.duration ?? 0 > 0 {
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                bar(fraction: fraction(at: context.date))
            }
        } else {
            bar(fraction: fraction(at: .now))
        }
    }

    private func fraction(at date: Date) -> Double {
        guard let duration = snapshot.duration, duration > 0 else { return 0 }
        var elapsed = snapshot.elapsed ?? 0
        if snapshot.isPlaying, let sampled = snapshot.timestamp {
            elapsed += date.timeIntervalSince(sampled) * (snapshot.playbackRate ?? 1)
        }
        return min(max(elapsed / duration, 0), 1)
    }

    private func bar(fraction: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.18))
                Capsule().fill(tint).frame(width: max(2, geo.size.width * fraction))
            }
        }
        .frame(height: 3)
    }
}
