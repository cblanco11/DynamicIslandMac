import AppKit

/// Exercises the display-change and wake paths without physically replugging a
/// display: asserts that rebuilding is idempotent (no duplicate or orphaned
/// panels), that bursts of `didChangeScreenParameters` coalesce into one
/// rebuild, and that `reassert()` restores the window rules a wake can drop.
///
///     DynamicIsland.app/Contents/MacOS/DynamicIsland -DILifecycleTest YES
@MainActor
enum LifecycleSelfTest {

    static var requested: Bool {
        UserDefaults.standard.bool(forKey: "DILifecycleTest")
    }

    static func run(panels: PanelManager) {
        Task {
            var failures = 0
            let expected = NSScreen.screens.count

            func check(_ label: String, _ condition: Bool) {
                if !condition { failures += 1 }
                print("   \(label.padding(toLength: 46, withPad: " ", startingAt: 0)) \(condition ? "PASS" : "FAIL")")
            }

            var panelCount: Int { NSApp.windows.filter { $0 is IslandPanel }.count }

            print("screens: \(expected)")
            print("\nidempotent rebuild")
            check("one panel per screen after first build", panelCount == expected)
            for _ in 0..<5 { panels.rebuild() }
            check("still one panel per screen after 5 rebuilds", panelCount == expected)
            check("manager agrees", panels.screenCount == expected)

            print("\ndebounced screen-parameter bursts")
            var rebuilds = 0
            let observer = ScreenObserver(
                onScreenChange: { rebuilds += 1; panels.rebuild() },
                onWake: { panels.reassert() }
            )
            for _ in 0..<8 {
                NotificationCenter.default.post(
                    name: NSApplication.didChangeScreenParametersNotification, object: nil)
            }
            try? await Task.sleep(for: .milliseconds(700))
            check("8 notifications coalesced into 1 rebuild (got \(rebuilds))", rebuilds == 1)
            check("no duplicate panels after burst", panelCount == expected)

            print("\nwake reassert")
            // Simulate what a wake can clobber.
            for window in NSApp.windows.compactMap({ $0 as? IslandPanel }) {
                window.level = .normal
                window.collectionBehavior = []
            }
            observer.tearDown()
            panels.reassert()
            let restored = NSApp.windows.compactMap { $0 as? IslandPanel }.allSatisfy {
                $0.level == IslandPanel.islandLevel
                    && $0.collectionBehavior == IslandPanel.islandCollectionBehavior
            }
            check("level and collection behaviour restored", restored)

            print(failures == 0 ? "\nRESULT: PASS" : "\nRESULT: FAIL (\(failures))")
            NSApp.terminate(nil)
        }
    }
}
