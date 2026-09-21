import AppKit

/// The only chrome the app has: a status item for quit, settings and the debug
/// toggles. There is no Dock icon and no menu bar.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {

    private let statusItem: NSStatusItem
    private let panels: PanelManager
    private let screens: ScreenObserver

    init(panels: PanelManager, screens: ScreenObserver) {
        self.panels = panels
        self.screens = screens
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "capsule.fill",
                                   accessibilityDescription: "Dynamic Island")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    // Rebuilt on open so the checkmarks always reflect live state.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let settings = NSMenuItem(title: "Settings…", action: nil, keyEquivalent: ",")
        settings.isEnabled = false
        menu.addItem(settings)

        menu.addItem(.separator())

        menu.addItem(toggle(title: "Debug Overlay",
                            isOn: panels.debugOverlayEnabled,
                            action: #selector(toggleDebugOverlay)))

        menu.addItem(toggle(title: "Force Synthetic Notch",
                            isOn: ScreenGeometry.forceSynthetic,
                            action: #selector(toggleSyntheticNotch)))

        let simulate = NSMenuItem(title: "Simulate Screen Change",
                                  action: #selector(simulateScreenChange),
                                  keyEquivalent: "")
        simulate.target = self
        menu.addItem(simulate)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Dynamic Island",
                              action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func toggle(title: String, isOn: Bool, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = isOn ? .on : .off
        return item
    }

    @objc private func toggleDebugOverlay() {
        panels.debugOverlayEnabled.toggle()
    }

    @objc private func toggleSyntheticNotch() {
        UserDefaults.standard.set(!ScreenGeometry.forceSynthetic, forKey: "DIForceSyntheticNotch")
        panels.rebuild()
    }

    @objc private func simulateScreenChange() {
        screens.simulateScreenChange()
    }
}
