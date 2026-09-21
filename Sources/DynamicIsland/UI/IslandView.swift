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
        let island = controller.currentSize

        ZStack(alignment: .top) {
            // The click target is the island silhouette, not the panel: the
            // panel extends past the shape by the shoulder margin. This sits
            // *below* the content -- above it, it would swallow every click
            // before the transport buttons ever saw one.
            IslandShape(size: island)
                .fill(Color.black)
                .contentShape(IslandShape(size: island))
                .onTapGesture { controller.islandClicked() }
                .animation(controller.animation, value: island)

            // Peek and hover carry nothing interactive, so they let clicks fall
            // through to the shape beneath. The expanded player needs its own
            // hit testing for the transport controls.
            IslandContentView(controller: controller)
                .frame(width: island.width, height: island.height)
                .allowsHitTesting(controller.state.isExpanded)
                .animation(controller.animation, value: island)

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
            // sit on top of the physical camera housing.
            Color.clear

        case .peek:
            media { snapshot in
                MediaPeekView(snapshot: snapshot, tint: tint,
                              notchWidth: controller.notch.rect.width)
            }

        case .hover:
            media { snapshot in
                MediaHoverView(snapshot: snapshot, tint: tint,
                               notchWidth: controller.notch.rect.width)
            }

        case .expanded:
            media { snapshot in
                MediaExpandedView(
                    snapshot: snapshot,
                    tint: tint,
                    onCommand: { controller.onTransport?($0) },
                    onDismiss: { controller.islandClicked() }
                )
            }
        }
    }

    private var tint: Color { Color(controller.tint) }

    /// Milestones 3 and 4 add `.level` and `.task`; until then anything that is
    /// not media draws nothing rather than guessing.
    @ViewBuilder
    private func media<Content: View>(
        @ViewBuilder _ content: (NowPlaying) -> Content
    ) -> some View {
        if case .nowPlaying(let snapshot)? = controller.displayedActivity?.kind {
            content(snapshot)
        } else {
            Color.clear
        }
    }
}
