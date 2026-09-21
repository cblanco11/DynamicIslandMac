import SwiftUI

/// The island outline: a squircle body whose **top** corners are inverted
/// (concave), so the shape flares outward and dissolves into the menu bar.
///
/// The path is a pure function of `rect`, which is the whole point -- SwiftUI
/// animates the view's frame and the path follows. One geometry change, never a
/// cross-fade between two shapes.
struct IslandShape: Shape {

    /// Radius of the concave top shoulders.
    var shoulderRadius: CGFloat = 12

    /// Nominal bottom corner radius before clamping.
    var bottomRadius: CGFloat = 24

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard rect.width > 0, rect.height > 0 else { return path }

        // Concave shoulders. Quarter circles, approximated as cubics so we never
        // have to reason about SwiftUI's arc winding in a y-down space.
        let r = min(shoulderRadius, rect.height / 2, rect.width / 2)
        let k = r * 0.5523

        // Bottom corners. `run` is the tangent run, `ctl` the control-point
        // distance from the edge: pulling it inside the circular 0.4477 gives
        // the continuous-curvature (squircle) feel rather than a plain arc.
        let nominal = min(bottomRadius, rect.width / 2, rect.height / 2)
        let run = min(nominal * 1.24, rect.width / 2, rect.height / 2)
        let ctl = run * 0.34

        let minX = rect.minX, maxX = rect.maxX
        let minY = rect.minY, maxY = rect.maxY

        // Top-left: start out in the menu bar and curve concavely into the body.
        path.move(to: CGPoint(x: minX - r, y: minY))
        path.addCurve(
            to: CGPoint(x: minX, y: minY + r),
            control1: CGPoint(x: minX - r + k, y: minY),
            control2: CGPoint(x: minX, y: minY + r - k)
        )

        // Left edge down into the bottom-left corner.
        path.addLine(to: CGPoint(x: minX, y: maxY - run))
        path.addCurve(
            to: CGPoint(x: minX + run, y: maxY),
            control1: CGPoint(x: minX, y: maxY - ctl),
            control2: CGPoint(x: minX + ctl, y: maxY)
        )

        // Bottom edge into the bottom-right corner.
        path.addLine(to: CGPoint(x: maxX - run, y: maxY))
        path.addCurve(
            to: CGPoint(x: maxX, y: maxY - run),
            control1: CGPoint(x: maxX - ctl, y: maxY),
            control2: CGPoint(x: maxX, y: maxY - ctl)
        )

        // Right edge up into the mirrored concave shoulder.
        path.addLine(to: CGPoint(x: maxX, y: minY + r))
        path.addCurve(
            to: CGPoint(x: maxX + r, y: minY),
            control1: CGPoint(x: maxX, y: minY + r - k),
            control2: CGPoint(x: maxX + r - k, y: minY)
        )

        path.closeSubpath()
        return path
    }
}
