import SwiftUI

/// The island's entire visual state, as a pure function of `IslandController`.
struct IslandView: View {
    let controller: IslandController

    var body: some View {
        let size = controller.currentSize

        VStack(spacing: 0) {
            IslandShape()
                .fill(Color.black)
                .frame(width: size.width, height: size.height)
                .animation(controller.animation, value: size)

            if controller.debugOverlayEnabled {
                DebugOverlay(controller: controller)
                    .padding(.top, 6)
                    .allowsHitTesting(false)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
