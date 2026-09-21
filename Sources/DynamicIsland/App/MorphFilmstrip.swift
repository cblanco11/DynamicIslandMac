import AppKit
import SwiftUI

/// Renders the morph frame by frame along real spring curves, so the transition
/// can be inspected without screen-recording an app that screen capture cannot
/// see. Each candidate becomes one row, sampled over a common wall-clock window
/// so the rows are directly comparable.
///
///     DynamicIsland.app/Contents/MacOS/DynamicIsland -DIExportMorph /tmp/morph
@MainActor
enum MorphFilmstrip {

    static var requestedPrefix: String? {
        UserDefaults.standard.string(forKey: "DIExportMorph")
    }

    private struct Candidate {
        let name: String
        let spring: Spring
    }

    static func exportAndExit(prefix: String) {
        let from = ScreenGeometry.syntheticNotchSize
        let to = IslandMetrics.expandedSize

        let candidates = [
            Candidate(name: "A current  (0.38 response / 0.78 damping)",
                      spring: Spring(response: 0.38, dampingRatio: 0.78)),
            Candidate(name: "B proposed (0.45 duration / 0.30 bounce)",
                      spring: Spring(duration: 0.45, bounce: 0.30)),
            Candidate(name: "C bouncier (0.55 duration / 0.42 bounce)",
                      spring: Spring(duration: 0.55, bounce: 0.42)),
        ]

        let frameCount = 6
        let window = 0.40                     // common sampling window, seconds
        let step = window / Double(frameCount - 1)
        let canvas = CGSize(width: 520, height: 170)

        var rows: [[NSImage]] = []
        for candidate in candidates {
            let settle = IslandMetrics.settleDuration(from: from, to: to, spring: candidate.spring)
            var peak: CGFloat = 0
            var t = 0.0
            while t < 2.0 {
                peak = max(peak, candidate.spring.value(fromValue: from.width, toValue: to.width,
                                                        initialVelocity: 0, time: t))
                t += 1.0 / 240.0
            }
            let overshoot = peak - to.width
            print(String(format: "%@\n   settles %@  peak width %.1f  overshoot %+.1fpt (%+.1f each side)",
                         candidate.name, "\(settle)", peak, overshoot, overshoot / 2))

            var row: [NSImage] = []
            for i in 0..<frameCount {
                let time = Double(i) * step
                let w = candidate.spring.value(fromValue: from.width, toValue: to.width,
                                               initialVelocity: 0, time: time)
                let h = candidate.spring.value(fromValue: from.height, toValue: to.height,
                                               initialVelocity: 0, time: time)
                if let image = render(size: CGSize(width: w, height: h), canvas: canvas) {
                    row.append(image)
                }
            }
            rows.append(row)
        }

        print(String(format: "\nrows sampled at %.0f %.0f %.0f %.0f %.0f %.0fms",
                     0.0, step * 1000, step * 2000, step * 3000, step * 4000, step * 5000))
        writeGrid(rows, canvas: canvas, to: URL(fileURLWithPath: "\(prefix)-compare.png"))
        NSApp.terminate(nil)
    }

    private static func render(size: CGSize, canvas: CGSize) -> NSImage? {
        let content = ZStack(alignment: .top) {
            VStack(spacing: 0) {
                Color(white: 0.32).frame(height: 33)   // menu bar
                Color(white: 0.62)                     // brighter desktop, for contrast
            }
            IslandShape(size: size)
                .fill(Color.black)
        }
        .frame(width: canvas.width, height: canvas.height)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        return renderer.nsImage
    }

    private static func writeGrid(_ rows: [[NSImage]], canvas: CGSize, to url: URL) {
        let cols = rows.map(\.count).max() ?? 0
        let size = CGSize(width: canvas.width * CGFloat(cols),
                          height: canvas.height * CGFloat(rows.count))
        let out = NSImage(size: size)
        out.lockFocus()
        for (r, row) in rows.enumerated() {
            for (c, image) in row.enumerated() {
                let y = size.height - CGFloat(r + 1) * canvas.height
                image.draw(in: CGRect(x: CGFloat(c) * canvas.width, y: y,
                                      width: canvas.width, height: canvas.height))
            }
        }
        out.unlockFocus()
        guard let tiff = out.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
        print("wrote \(url.path)")
    }
}
