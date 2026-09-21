import SwiftUI

/// State + frame rate readout. Never hit-tested, and its display link only runs
/// while it is visible, so the idle app schedules nothing.
struct DebugOverlay: View {
    let controller: IslandController

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            row("state", stateLabel)
            row("fps", String(format: "%.0f", controller.frameRate))
            row("notch", String(format: "%.0f x %.0f%@",
                                controller.notch.rect.width,
                                controller.notch.rect.height,
                                controller.notch.isSynthetic ? " (synthetic)" : ""))
            row("morphing", controller.isMorphing ? "yes" : "no")
            row("reduceMotion", controller.reduceMotion ? "yes" : "no")
        }
        .font(.system(size: 9, weight: .medium, design: .monospaced))
        .padding(6)
        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 6))
        .foregroundStyle(.white)
    }

    private var stateLabel: String {
        switch controller.state {
        case .closed:            "closed"
        case .peek(let a):       "peek(\(a.id))"
        case .hover(let a):      "hover(\(a.id))"
        case .expanded:          "expanded"
        }
    }

    private func row(_ key: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(key).foregroundStyle(.white.opacity(0.55))
            Text(value)
        }
    }
}
