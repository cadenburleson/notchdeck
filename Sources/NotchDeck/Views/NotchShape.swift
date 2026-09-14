import SwiftUI

/// The classic notch silhouette: concave "ears" along the flat edge that blend
/// into the screen border, convex rounded corners on the free side.
/// `edge` picks which side of the rect is the flat one.
struct NotchShape: Shape {
    var edge: NotchEdge = .top
    var earRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(earRadius, bottomRadius) }
        set { earRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        switch edge {
        case .top:
            return topPath(in: rect)
        case .left:
            // Draw as if the flat side were on top, then rotate -90° so it lands on the left.
            let base = topPath(in: CGRect(x: 0, y: 0, width: rect.height, height: rect.width))
            let t = CGAffineTransform(translationX: rect.minX, y: rect.minY + rect.height)
                .rotated(by: -.pi / 2)
            return base.applying(t)
        case .right:
            let base = topPath(in: CGRect(x: 0, y: 0, width: rect.height, height: rect.width))
            let t = CGAffineTransform(translationX: rect.minX + rect.width, y: rect.minY)
                .rotated(by: .pi / 2)
            return base.applying(t)
        }
    }

    private func topPath(in rect: CGRect) -> Path {
        let e = earRadius
        let b = max(0, min(bottomRadius, (rect.height - e) / 2, (rect.width - 2 * e) / 2))
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + e, y: rect.minY + e),
                       control: CGPoint(x: rect.minX + e, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + e, y: rect.maxY - b))
        p.addQuadCurve(to: CGPoint(x: rect.minX + e + b, y: rect.maxY),
                       control: CGPoint(x: rect.minX + e, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - e - b, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - e, y: rect.maxY - b),
                       control: CGPoint(x: rect.maxX - e, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - e, y: rect.minY + e))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                       control: CGPoint(x: rect.maxX - e, y: rect.minY))
        p.closeSubpath()
        return p
    }
}
