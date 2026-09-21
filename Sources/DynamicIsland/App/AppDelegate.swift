import AppKit
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let panels = PanelManager()
    private var screens: ScreenObserver?
    private var statusItem: StatusItemController?
    private let log = Logger(subsystem: "com.jeffreyotoo.DynamicIsland", category: "app")

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let prefix = SnapshotExporter.requestedPrefix {
            SnapshotExporter.exportAndExit(prefix: prefix)
            return
        }

        if PassThroughSelfTest.requested {
            PassThroughSelfTest.run()
            return
        }

        panels.rebuild()

        let observer = ScreenObserver(
            onScreenChange: { [weak self] in
                self?.log.info("screen parameters changed; rebuilding")
                self?.panels.rebuild()
            },
            onWake: { [weak self] in
                self?.panels.reassert()
            }
        )
        screens = observer
        statusItem = StatusItemController(panels: panels, screens: observer)

        log.info("launched with \(self.panels.screenCount, privacy: .public) panel(s)")
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
