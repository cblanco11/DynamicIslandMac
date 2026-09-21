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

        if let prefix = LiveMorphCapture.requestedPrefix {
            LiveMorphCapture.run(prefix: prefix)
            return
        }

        if let prefix = MorphFilmstrip.requestedPrefix {
            MorphFilmstrip.exportAndExit(prefix: prefix)
            return
        }

        if PassThroughSelfTest.requested {
            PassThroughSelfTest.run()
            return
        }

        panels.rebuild()

        if LifecycleSelfTest.requested {
            LifecycleSelfTest.run(panels: panels)
            return
        }

        let observer = ScreenObserver(
            onScreenChange: { [weak self] in
                self?.log.notice("screen parameters changed; rebuilding")
                self?.panels.rebuild()
            },
            onWake: { [weak self] in
                self?.panels.reassert()
            }
        )
        screens = observer
        statusItem = StatusItemController(panels: panels, screens: observer)

        log.notice("launched: \(self.panels.screenCount, privacy: .public) panel(s), status item ready")
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
