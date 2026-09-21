import AppKit

/// Does a real mouse click actually reach the island?
///
/// The panel is `.nonactivatingPanel` and returns false from `canBecomeKey`, and
/// SwiftUI controls sometimes refuse to respond in a window that is not key. The
/// island is useless if clicking it does nothing, and this cannot be checked
/// from outside: screen-capture tools will not drive clicks into an
/// `LSUIElement` app. So the event is synthesised and delivered through the real
/// `NSWindow.sendEvent` path.
///
///     DynamicIsland.app/Contents/MacOS/DynamicIsland -DIClickTest YES
@MainActor
enum ClickSelfTest {

    static var requested: Bool { UserDefaults.standard.bool(forKey: "DIClickTest") }

    static func run() {
        guard let screen = NSScreen.main else { NSApp.terminate(nil); return }
        let notch = ScreenGeometry.notch(for: screen)
        let controller = IslandController(notch: notch)

        var snapshot = NowPlaying()
        snapshot.trackID = "clicktest"
        snapshot.title = "Click Test"
        snapshot.duration = 120
        snapshot.elapsed = 10
        let activity = Activity(id: "media", priority: .ambient, kind: .nowPlaying(snapshot))

        let panel = IslandPanel(screen: screen, controller: controller)
        panel.orderFrontRegardless()
        controller.present(activity)

        var failures = 0
        func check(_ label: String, _ ok: Bool) {
            if !ok { failures += 1 }
            print("   \(label.padding(toLength: 44, withPad: " ", startingAt: 0)) \(ok ? "PASS" : "FAIL")")
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            print("key window: \(panel.isKeyWindow), canBecomeKey: \(panel.canBecomeKey)")
            print("state before click: \(controller.state.logDescription)\n")

            check("resting in peek", controller.state.activity != nil && !controller.state.isExpanded)

            click(panel, controller)
            try? await Task.sleep(for: .milliseconds(900))
            print("   state after 1st click: \(controller.state.logDescription)")
            check("click opened the full player", controller.state.isExpanded)

            click(panel, controller)
            try? await Task.sleep(for: .milliseconds(900))
            print("   state after 2nd click: \(controller.state.logDescription)")
            check("second click closed it again", !controller.state.isExpanded)

            // A tap gesture is not proof that SwiftUI Buttons work here:
            // buttons are stricter about key-window state, and the transport
            // controls are the whole point of the expanded player.
            var received: [MediaRemoteHelper.Command] = []
            controller.onTransport = { received.append($0) }

            click(panel, controller)                       // reopen
            try? await Task.sleep(for: .milliseconds(900))
            check("reopened for the button test", controller.state.isExpanded)

            clickTransportPlayPause(panel, controller)
            try? await Task.sleep(for: .milliseconds(700))
            print("   commands received: \(received)")
            check("play/pause button fired", received.contains(.togglePlayPause))

            print(failures == 0
                  ? "\nRESULT: PASS -- clicks and transport buttons work in a non-key panel"
                  : "\nRESULT: FAIL (\(failures))")
            NSApp.terminate(nil)
        }
    }

    /// Centre of the island, in the panel's coordinates.
    private static func click(_ panel: IslandPanel, _ controller: IslandController) {
        let frame = controller.islandFrame
        send(panel, at: NSPoint(x: frame.midX, y: panel.frame.height - frame.midY))
    }

    /// The play/pause control sits centred in the transport row, which is the
    /// last 39pt of the expanded island.
    private static func clickTransportPlayPause(_ panel: IslandPanel, _ controller: IslandController) {
        let frame = controller.islandFrame
        let yFromTop = frame.height - 39
        send(panel, at: NSPoint(x: frame.midX, y: panel.frame.height - (frame.minY + yFromTop)))
    }

    private static func send(_ panel: IslandPanel, at point: NSPoint) {

        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let event = NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: panel.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0
            ) else { continue }
            panel.sendEvent(event)
        }
    }
}
