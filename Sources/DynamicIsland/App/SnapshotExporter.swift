import AppKit
import SwiftUI

/// Renders the island's real view hierarchy to PNGs and exits.
///
/// An `LSUIElement` app cannot be granted screen-capture visibility, so the
/// island never appears in a normal screenshot. Rather than eyeball a filtered
/// capture, the app draws itself: this exercises `IslandView` and `IslandShape`
/// exactly as the panel does.
///
///     DynamicIsland.app/Contents/MacOS/DynamicIsland -DIExportSnapshot /tmp/island
///
/// writes `/tmp/island-closed.png` and `/tmp/island-expanded.png`, then quits.
@MainActor
enum SnapshotExporter {

    static var requestedPrefix: String? {
        UserDefaults.standard.string(forKey: "DIExportSnapshot")
    }

    static func exportAndExit(prefix: String) {
        // Fixed geometry so snapshots are reproducible on any machine.
        let notch = NotchGeometry(
            rect: CGRect(x: 0, y: 0,
                         width: ScreenGeometry.syntheticNotchSize.width,
                         height: ScreenGeometry.syntheticNotchSize.height),
            isSynthetic: false
        )

        for (name, state) in [("closed", IslandState.closed), ("expanded", IslandState.expanded)] {
            let controller = IslandController(notch: notch)
            controller.forceState(state)
            let url = URL(fileURLWithPath: "\(prefix)-\(name).png")
            if render(controller: controller, to: url) {
                FileHandle.standardError.write(Data("wrote \(url.path)\n".utf8))
            } else {
                FileHandle.standardError.write(Data("FAILED to render \(url.path)\n".utf8))
            }
            controller.tearDown()
        }

        NSApp.terminate(nil)
    }

    private static func render(controller: IslandController, to url: URL) -> Bool {
        // Fixed canvas, larger than any island state, so the two snapshots
        // are directly comparable and the shoulders are never clipped.
        let size = CGSize(width: 640, height: 220)

        let content = ZStack(alignment: .top) {
            // Stand-in for the menu bar strip and the desktop below it, so the
            // concave shoulders are actually legible against something.
            VStack(spacing: 0) {
                Color(white: 0.32).frame(height: 33)
                Color(white: 0.16)
            }
            IslandView(controller: controller)
        }
        .frame(width: size.width, height: size.height)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2

        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else { return false }

        return (try? png.write(to: url)) != nil
    }
}
