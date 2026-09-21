import AppKit
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let panels = PanelManager()
    private let registry = ActivityRegistry()
    private let media = MediaActivityProvider()
    private var signalSources: [any DispatchSourceSignal] = []
    private var screens: ScreenObserver?
    private var statusItem: StatusItemController?
    private let log = Logger(subsystem: "com.jeffreyotoo.DynamicIsland", category: "app")

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let prefix = SnapshotExporter.requestedPrefix {
            SnapshotExporter.exportAndExit(prefix: prefix)
            return
        }

        if ClickSelfTest.requested {
            ClickSelfTest.run()
            return
        }

        if MediaProbe.requested {
            MediaProbe.run()
            return
        }

        if MediaRemoteProbe.requested {
            MediaRemoteProbe.run()
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

        startActivities()

        log.notice("launched: \(self.panels.screenCount, privacy: .public) panel(s), status item ready")
    }

    /// A SIGTERM (`pkill`, a `make run` restart) otherwise skips
    /// `applicationWillTerminate`, leaving the helper orphaned.
    private func installSignalHandlers() {
        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { [weak self] in
                self?.registry.stopAll()
                NSApp.terminate(nil)
            }
            source.resume()
            signalSources.append(source)
        }
    }

    private func startActivities() {
        let reaped = MediaRemoteHelper.reapOrphanedHelpers()
        if reaped > 0 { log.notice("reaped \(reaped, privacy: .public) orphaned helper(s)") }
        installSignalHandlers()

        panels.setTransportHandler { [weak self] command in
            self?.media.send(command)
        }
        registry.onChange = { [weak self] activity in
            guard let self else { return }
            let tint: NSColor
            if case .nowPlaying(let snapshot)? = activity?.kind {
                tint = media.tint(for: snapshot)
            } else {
                tint = ArtworkColor.fallback
            }
            panels.present(activity, tint: tint)
        }
        registry.register(media)
    }

    func applicationWillTerminate(_ notification: Notification) {
        registry.stopAll()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
