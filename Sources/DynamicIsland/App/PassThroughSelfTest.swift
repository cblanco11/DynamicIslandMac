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
            let panel = IslandPanel(screen: screen, controller: controller)
            panel.orderFrontRegardless()
            try? await Task.sleep(for: .milliseconds(600))

            print("screen \(screen.frame)  notch \(notch.rect)")
            print("panel  \(panel.frame)")

            let failures = probe(panel: panel, screen: screen, notch: notch)
            print(failures == 0 ? "\nRESULT: PASS" : "\nRESULT: FAIL (\(failures))")
            NSApp.terminate(nil)
        }
    }

    private static func probe(panel: IslandPanel, screen: NSScreen, notch: NotchGeometry) -> Int {
        let p = panel.frame
        let probes: [(String, NSPoint, Bool)] = [
            ("island centre",          NSPoint(x: notch.rect.midX, y: notch.rect.midY), true),
            ("menu bar left of panel", NSPoint(x: p.minX - 40, y: notch.rect.midY), false),
            ("menu bar right of panel",NSPoint(x: p.maxX + 40, y: notch.rect.midY), false),
            ("below the island",       NSPoint(x: notch.rect.midX, y: p.minY - 40), false),
            ("far left menu bar",      NSPoint(x: screen.frame.minX + 200, y: notch.rect.midY), false),
        ]

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
        return failures
    }
}
