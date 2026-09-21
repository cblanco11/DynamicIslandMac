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

            if controller.debugOverlayEnabled {
                DebugOverlay(controller: controller)
                    .offset(y: IslandMetrics.expandedSize.height + 6)
                    .allowsHitTesting(false)
            }
        }
        // Tracks the window, which resizes instantly at transition boundaries.
        // Animating it would desynchronise the two.
        .frame(width: panel.width, height: panel.height, alignment: .top)
        .animation(nil, value: panel)
    }
}
