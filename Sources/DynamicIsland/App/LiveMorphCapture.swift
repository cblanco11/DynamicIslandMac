import AppKit
import SwiftUI
import QuartzCore

/// Captures what the app *actually renders* during a real hover-driven morph,
/// in screen coordinates, and reports the island's true edges over time.
///
/// The filmstrip in `MorphFilmstrip` renders a model of the spring. This does
/// not model anything: it drives the production hover path, captures the live
/// view each display tick, and measures the black pixels. If the rendered
/// geometry disagrees with the model, this is the one that is right.
///
///     DynamicIsland.app/Contents/MacOS/DynamicIsland -DICaptureMorph /tmp/live
@MainActor
final class LiveMorphCapture {

    static var requestedPrefix: String? {
        UserDefaults.standard.string(forKey: "DICaptureMorph")
    }

    private struct Sample {
        let time: CFTimeInterval
        let panelFrame: CGRect
        let image: NSBitmapImageRep
    }

    private var samples: [Sample] = []
    private var link: CADisplayLink?
    private var start: CFTimeInterval = 0
    private let prefix: String
    private var panel: IslandPanel?
    private var controller: IslandController?

    init(prefix: String) { self.prefix = prefix }

    private static var shared: LiveMorphCapture?

    static func run(prefix: String) {
        let capture = LiveMorphCapture(prefix: prefix)
        shared = capture
        capture.begin()
    }

    private func begin() {
        guard let screen = NSScreen.main else { NSApp.terminate(nil); return }
        let notch = ScreenGeometry.notch(for: screen)
        let controller = IslandController(notch: notch)
        let panel = IslandPanel(screen: screen, controller: controller)
        panel.orderFrontRegardless()
        self.controller = controller
        self.panel = panel

        print("screen \(screen.frame)")
        print("notch  \(notch.rect)   (closed island should match this exactly)")

        // Seed an activity, or `mouseEntered` guards out and the whole capture
        // passes vacuously with the island never leaving `.closed`.
        var snapshot = NowPlaying()
        snapshot.trackID = "selftest"
        snapshot.title = "Self Test"
        snapshot.artist = "DynamicIsland"
        snapshot.duration = 180
        snapshot.elapsed = 42
        controller.restore(
            activity: Activity(id: "media", priority: .ambient, kind: .nowPlaying(snapshot)),
            tint: ArtworkColor.fallback
        )

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            guard let view = panel.contentView else { return }
            start = CACurrentMediaTime()
            let link = view.displayLink(target: self, selector: #selector(tick(_:)))
            link.add(to: .main, forMode: .common)
            self.link = link

            // Drive the real production path, not a shortcut, through every
            // resize the island can make: closed -> hover -> expanded -> back.
            controller.present(controller.restingActivity)
            try? await Task.sleep(for: .milliseconds(700))
            controller.mouseEntered()
            try? await Task.sleep(for: .milliseconds(900))
            controller.islandClicked()
            try? await Task.sleep(for: .milliseconds(1100))
            controller.islandClicked()
            try? await Task.sleep(for: .milliseconds(900))
            self.finish()
        }
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard let panel, let view = panel.contentView else { return }
        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0,
              let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        view.cacheDisplay(in: bounds, to: rep)
        samples.append(Sample(time: CACurrentMediaTime() - start,
                              panelFrame: panel.frame,
                              image: rep))


    }

    private func finish() {
        link?.invalidate()
        link = nil

        print("\ncaptured \(samples.count) frames")
        print("\n    t      panel w x h      island in SCREEN coords            growth")
        print("                             left    right    top   bottom    L     R    down")

        var first: (l: CGFloat, r: CGFloat, b: CGFloat)?
        for sample in samples where Int(sample.time * 1000) % 33 < 17 {
            guard let box = blackBounds(sample.image) else { continue }
            // Bitmap origin is top-left; panel frame is AppKit Y-up.
            let scale = CGFloat(sample.image.pixelsWide) / sample.panelFrame.width
            let left = sample.panelFrame.minX + box.minX / scale
            let right = sample.panelFrame.minX + box.maxX / scale
            let top = sample.panelFrame.maxY - box.minY / scale
            let bottom = sample.panelFrame.maxY - box.maxY / scale
            if first == nil { first = (left, right, bottom) }
            let f = first!
            print(String(format: "  %5.0fms  %5.0f x %5.0f   %7.1f %7.1f %6.1f %7.1f  %5.1f %5.1f %6.1f",
                         sample.time * 1000, sample.panelFrame.width, sample.panelFrame.height,
                         left, right, top, bottom,
                         f.l - left, right - f.r, f.b - bottom))
        }

        // The one invariant that matters: the island is welded to the top of
        // the screen for the whole morph. If it ever leaves, the island has
        // visibly detached from the notch.
        let screenTop = NSScreen.main?.frame.maxY ?? 0
        var worstDrift: CGFloat = 0
        var worstTime: Double = 0
        var measured = 0
        for sample in samples {
            guard let box = blackBounds(sample.image) else { continue }
            measured += 1
            let scale = CGFloat(sample.image.pixelsWide) / sample.panelFrame.width
            let drift = screenTop - (sample.panelFrame.maxY - box.minY / scale)
            if drift > worstDrift { worstDrift = drift; worstTime = sample.time }
        }
        print(String(format: "\n%d frames measured, screen top %.0f", measured, screenTop))
        print(String(format: "max top-edge drift: %.1fpt at %.0fms", worstDrift, worstTime * 1000))
        print(worstDrift <= 1.0 && measured > 0
              ? "RESULT: PASS -- island stays welded to the screen top"
              : "RESULT: FAIL -- island detaches from the notch mid-morph")

        writeStrip()
        NSApp.terminate(nil)
    }

    /// Bounding box of non-transparent dark pixels, in bitmap pixel coords.
    private func blackBounds(_ rep: NSBitmapImageRep) -> CGRect? {
        guard let data = rep.bitmapData else { return nil }
        let w = rep.pixelsWide, h = rep.pixelsHigh
        let spp = rep.samplesPerPixel, rowBytes = rep.bytesPerRow
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            let row = data + y * rowBytes
            for x in 0..<w {
                let p = row + x * spp
                let alpha = spp >= 4 ? p[3] : 255
                guard alpha > 128, p[0] < 90, p[1] < 90, p[2] < 90 else { continue }
                if x < minX { minX = x }; if x > maxX { maxX = x }
                if y < minY { minY = y }; if y > maxY { maxY = y }
            }
        }
        guard maxX >= 0 else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    private func writeStrip() {
        let picks = stride(from: 0, to: samples.count, by: max(1, samples.count / 10)).map { samples[$0] }
        guard let widest = picks.map(\.panelFrame.width).max(),
              let tallest = picks.map(\.panelFrame.height).max() else { return }
        let cell = CGSize(width: widest + 40, height: tallest + 40)
        let out = NSImage(size: CGSize(width: cell.width * CGFloat(picks.count), height: cell.height))
        out.lockFocus()
        NSColor(white: 0.62, alpha: 1).setFill()
        CGRect(origin: .zero, size: out.size).fill()
        for (i, sample) in picks.enumerated() {
            let image = NSImage(size: sample.panelFrame.size)
            image.addRepresentation(sample.image)
            // Keep each frame anchored the way it sits on screen: top-aligned, centred.
            let x = CGFloat(i) * cell.width + (cell.width - sample.panelFrame.width) / 2
            let y = cell.height - 20 - sample.panelFrame.height
            image.draw(in: CGRect(x: x, y: y,
                                  width: sample.panelFrame.width, height: sample.panelFrame.height))
        }
        out.unlockFocus()
        guard let tiff = out.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        let url = URL(fileURLWithPath: "\(prefix)-live.png")
        try? png.write(to: url)
        print("\nwrote \(url.path)")
    }
}
