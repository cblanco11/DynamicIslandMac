import SwiftUI

/// The island's entire visual state, as a pure function of `IslandController`.
///
/// The view's frame is the panel and never animates; the morph lives entirely in
/// `IslandShape.animatableData`. See `IslandShape` for why the size must not
/// drive a layout frame.
struct IslandView: View {
    let controller: IslandController

    var body: some View {
        let panel = controller.panelSize

        ZStack(alignment: .top) {
            IslandShape(size: controller.currentSize)
                .fill(Color.black)
                .animation(controller.animation, value: controller.currentSize)

            IslandContentView(controller: controller)
                .frame(width: controller.currentSize.width,
                       height: controller.currentSize.height)
                .animation(controller.animation, value: controller.currentSize)

            if controller.debugOverlayEnabled {
                DebugOverlay(controller: controller)
                    .offset(y: IslandMetrics.expandedSize.height + 6)
                    .allowsHitTesting(false)
            }
        }
        // Tracks the window, which resizes at transition boundaries only.
        // Animating it would desynchronise the two.
        .frame(width: panel.width, height: panel.height, alignment: .top)
        .animation(nil, value: panel)
    }
}

/// What sits inside the island shape. Exhaustive over `ActivityKind`, so adding
/// a provider is a compile error until the island knows how to draw it.
struct IslandContentView: View {
    let controller: IslandController

    var body: some View {
        switch controller.state {
        case .closed:
            // The closed island is exactly the notch. Anything drawn here would
            // be drawn on top of the physical camera housing.
            Color.clear

        case .peek:
            if case .nowPlaying(let snapshot)? = controller.displayedActivity?.kind {
                MediaPeekView(snapshot: snapshot,
                              tint: Color(controller.tint),
                              notchWidth: controller.notch.rect.width)
            } else {
                Color.clear
            }

        case .expanded:
            switch controller.displayedActivity?.kind {
            case .nowPlaying(let snapshot):
                MediaExpandedView(snapshot: snapshot,
                                  tint: Color(controller.tint)) { command in
                    controller.onTransport?(command)
                }
            case .task, .level, .none:
                // Milestones 3 and 4.
                Color.clear
            }
        }
    }
}
