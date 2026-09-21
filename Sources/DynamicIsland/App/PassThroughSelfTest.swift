import AppKit

/// Determines, empirically, whether mouse events actually pass through the
/// panel outside the island.
///
/// `hitTest` returning nil is an AppKit-level decision; whether the click then
/// reaches the window underneath is the window server's call.
/// `NSWindow.windowNumber(at:belowWindowWithWindowNumber:)` performs the same
/// shaped hit test the server uses to route a real click.
///
/// Three configurations are probed so a failure can be attributed rather than
/// guessed at, and so the oracle itself is validated: config C is a known-good
/// pass-through, so if C does not differ from A the oracle is not measuring
/// click routing at all and the result means nothing.
///
///     DynamicIsland.app/Contents/MacOS/DynamicIsland -DISelfTest YES
@MainActor
enum PassThroughSelfTest {

    static var requested: Bool {
        UserDefaults.standard.bool(forKey: "DISelfTest")
    }

    static func run() {
        Task {
            guard let screen = NSScreen.main else { NSApp.terminate(nil); return }
            let notch = ScreenGeometry.notch(for: screen)
            let controller = IslandController(notch: notch)

            print("screen \(screen.frame)  notch \(notch.rect)")

            // A: exactly as shipped.
            let a = IslandPanel(screen: screen, controller: controller)
            a.orderFrontRegardless()
            try? await Task.sleep(for: .milliseconds(500))
            probe("A  as shipped (NSHostingView + hitTest)", panel: a, screen: screen, notch: notch)

            // B: no SwiftUI at all -- a bare transparent content view. Isolates
            // whether NSHostingView's layer is what captures the clicks.
            a.contentView = NSView(frame: CGRect(origin: .zero, size: IslandMetrics.panelSize))
            try? await Task.sleep(for: .milliseconds(500))
            probe("B  bare transparent NSView, no hitTest override", panel: a, screen: screen, notch: notch)

            // C: known-good pass-through. Validates the oracle.
            a.ignoresMouseEvents = true
            try? await Task.sleep(for: .milliseconds(500))
            probe("C  ignoresMouseEvents = true (control)", panel: a, screen: screen, notch: notch)

            NSApp.terminate(nil)
        }
    }

    private static func probe(_ label: String, panel: IslandPanel, screen: NSScreen, notch: NotchGeometry) {
        let panelRect = panel.frame
        let probes: [(String, NSPoint, Bool)] = [
            ("island centre",           NSPoint(x: notch.rect.midX, y: notch.rect.midY), true),
            ("panel, left of island",   NSPoint(x: panelRect.minX + 30, y: panelRect.midY), false),
            ("panel, below island",     NSPoint(x: notch.rect.midX, y: panelRect.minY + 20), false),
            ("menu bar, left of notch", NSPoint(x: panelRect.minX + 10, y: notch.rect.midY), false),
        ]

        print("\n\(label)")
        var failures = 0
        for (name, point, expectPanel) in probes {
            let number = NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: 0)
            let hitPanel = number == panel.windowNumber
            let ok = hitPanel == expectPanel
            if !ok { failures += 1 }
            print("   \(name.padding(toLength: 24, withPad: " ", startingAt: 0))"
                  + " -> win \(number)  panel=\(hitPanel ? "yes" : "no ")"
                  + "  want=\(expectPanel ? "yes" : "no ")  \(ok ? "PASS" : "FAIL")")
        }
        print("   => \(failures == 0 ? "PASS" : "FAIL (\(failures))")")
    }
}
