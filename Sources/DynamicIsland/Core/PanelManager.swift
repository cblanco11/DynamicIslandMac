import AppKit
import os

/// One panel + controller per attached screen, rebuilt on display changes.
@MainActor
final class PanelManager {

    private struct Entry {
        let panel: IslandPanel
        let controller: IslandController
    }

    private var entries: [CGDirectDisplayID: Entry] = [:]
    private let log = Logger(subsystem: "com.jeffreyotoo.DynamicIsland", category: "panels")

    var screenCount: Int { entries.count }

    /// Idempotent: creates panels for new screens, repositions existing ones,
    /// tears down panels for screens that went away.
    func rebuild() {
        let screens = NSScreen.screens
        ScreenGeometry.pruneCache(keeping: screens)

        var live: Set<CGDirectDisplayID> = []

        for screen in screens {
            guard let id = ScreenGeometry.displayID(for: screen) else {
                log.error("screen with no NSScreenNumber; skipping")
                continue
            }
            live.insert(id)
            let notch = ScreenGeometry.notch(for: screen)

            if let entry = entries[id] {
                entry.controller.resetImmediately()
                entry.controller.update(notch: notch)
                entry.panel.applyWindowRules()
                entry.panel.reposition(on: screen)
                entry.panel.orderFrontRegardless()
            } else {
                let controller = IslandController(notch: notch)
                let panel = IslandPanel(screen: screen, controller: controller)
                panel.orderFrontRegardless()
                entries[id] = Entry(panel: panel, controller: controller)
                log.notice("""
                    built panel for display \(id, privacy: .public) \
                    notch \(notch.rect.width, privacy: .public)x\(notch.rect.height, privacy: .public) \
                    synthetic=\(notch.isSynthetic, privacy: .public)
                    """)
            }
        }

        for (id, entry) in entries where !live.contains(id) {
            entry.controller.tearDown()
            entry.panel.orderOut(nil)
            entry.panel.close()
            entries.removeValue(forKey: id)
            log.notice("tore down panel for departed display \(id, privacy: .public)")
        }
    }

    /// Window level and collection behaviour can be dropped across sleep/wake,
    /// so re-assert rather than trusting what was set at construction.
    func reassert() {
        for screen in NSScreen.screens {
            guard let id = ScreenGeometry.displayID(for: screen), let entry = entries[id] else { continue }
            entry.panel.applyWindowRules()
            entry.panel.reposition(on: screen)
            entry.panel.orderFrontRegardless()
        }
    }

    var debugOverlayEnabled: Bool {
        get { entries.values.first?.controller.debugOverlayEnabled ?? false }
        set { for entry in entries.values { entry.controller.debugOverlayEnabled = newValue } }
    }
}
