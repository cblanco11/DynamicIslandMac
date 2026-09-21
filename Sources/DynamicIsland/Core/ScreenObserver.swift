import AppKit

/// Debounced display-change and wake notifications.
@MainActor
final class ScreenObserver {

    /// `didChangeScreenParameters` arrives in bursts during a reconfiguration;
    /// coalesce so we rebuild once, not five times.
    private static let debounce: Duration = .milliseconds(250)

    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var pending: Task<Void, Never>?

    private let onScreenChange: @MainActor () -> Void
    private let onWake: @MainActor () -> Void

    init(onScreenChange: @escaping @MainActor () -> Void,
         onWake: @escaping @MainActor () -> Void) {
        self.onScreenChange = onScreenChange
        self.onWake = onWake

        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) { [weak self] in
            self?.scheduleScreenChange()
        }
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification) { [weak self] in
            self?.onWake()
        }
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.screensDidWakeNotification) { [weak self] in
            self?.onWake()
        }
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.activeSpaceDidChangeNotification) { [weak self] in
            self?.onWake()
        }
    }

    /// Same constraint as `IslandController.tearDown`: a nonisolated `deinit`
    /// cannot touch MainActor-isolated, non-Sendable state under Swift 6. This
    /// observer is held by `AppDelegate` for the whole process lifetime, so
    /// teardown is offered for completeness rather than because it is reached.
    func tearDown() {
        pending?.cancel()
        pending = nil
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
    }

    private func observe(_ center: NotificationCenter,
                         _ name: Notification.Name,
                         _ body: @escaping @MainActor () -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { body() }
        }
        observers.append((center, token))
    }

    private func scheduleScreenChange() {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled, let self else { return }
            onScreenChange()
        }
    }

    /// Used by the debug menu item to exercise the rebuild path without
    /// physically replugging a display.
    func simulateScreenChange() {
        scheduleScreenChange()
    }
}
