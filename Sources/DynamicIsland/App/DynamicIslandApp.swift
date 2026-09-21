import AppKit

/// Plain AppKit entry point. No SwiftUI `App`, no storyboard: the app owns raw
/// `NSPanel`s, which the SwiftUI scene lifecycle cannot express.
@main
@MainActor
enum DynamicIslandApp {
    /// Held for the process lifetime; `NSApplication.delegate` is a weak reference.
    private static let delegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        // Belt and braces alongside LSUIElement in Info.plist.
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
