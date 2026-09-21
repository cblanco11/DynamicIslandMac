import SwiftUI

/// The playing indicator.
///
/// While playing, bars rise and fall; while paused, it collapses to a single
/// play glyph rather than a row of flat bars, so the resting island always says
/// what a click will do.
///
/// Driven by `TimelineView`, which stops scheduling the moment playback pauses --
/// an idle island must not be running an animation.
struct Waveform: View {
    let isPlaying: Bool
    let tint: Color
    var barCount: Int = 4
    var barWidth: CGFloat = 2.5
    var maxHeight: CGFloat = 14

    var body: some View {
        if isPlaying {
            TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { context in
                bars(at: context.date.timeIntervalSinceReferenceDate)
            }
        } else {
            Image(systemName: "play.fill")
                .font(.system(size: maxHeight * 0.85, weight: .semibold))
                .foregroundStyle(tint)
                .frame(height: maxHeight)
        }
    }

    private func bars(at time: TimeInterval) -> some View {
        HStack(alignment: .center, spacing: barWidth * 0.8) {
            ForEach(0..<barCount, id: \.self) { i in
                // Two detuned sines per bar so the row never visibly loops.
                let a = sin(time * 5.1 + Double(i) * 1.7)
                let b = sin(time * 3.3 + Double(i) * 0.9)
                let level = 0.5 + 0.28 * a + 0.22 * b
                Capsule()
                    .fill(tint)
                    .frame(width: barWidth,
                           height: max(barWidth, maxHeight * CGFloat(0.25 + 0.75 * level)))
            }
        }
        .frame(height: maxHeight)
    }
}

/// Small rounded artwork, with a placeholder when a track has none.
struct ArtworkThumb: View {
    let snapshot: NowPlaying
    let tint: Color
    let side: CGFloat
    var corner: CGFloat = 6

    var body: some View {
        Group {
            if let image = ArtworkCache.image(for: snapshot) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                tint.opacity(0.32).overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: side * 0.42, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85)))
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}
