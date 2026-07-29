import SwiftUI

struct MacWallMenuBarMark: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(
                x: rect.minX + (x / 656) * rect.width,
                y: rect.minY + (y / 458) * rect.height
            )
        }

        var path = Path()

        path.move(to: point(72, 0))
        path.addLine(to: point(116, 0))
        path.addLine(to: point(328, 175))
        path.addLine(to: point(540, 0))
        path.addLine(to: point(584, 0))
        path.addQuadCurve(to: point(602, 19), control: point(602, 0))
        path.addLine(to: point(602, 385))
        path.addQuadCurve(to: point(584, 403), control: point(602, 403))
        path.addLine(to: point(72, 403))
        path.addQuadCurve(to: point(54, 385), control: point(54, 403))
        path.addLine(to: point(54, 19))
        path.addQuadCurve(to: point(72, 0), control: point(54, 0))
        path.closeSubpath()

        path.move(to: point(116, 88))
        path.addLine(to: point(116, 344))
        path.addLine(to: point(540, 344))
        path.addLine(to: point(540, 88))
        path.addLine(to: point(328, 262))
        path.closeSubpath()

        path.move(to: point(0, 422))
        path.addLine(to: point(656, 422))
        path.addQuadCurve(to: point(637, 450), control: point(652, 441))
        path.addQuadCurve(to: point(603, 458), control: point(625, 458))
        path.addLine(to: point(53, 458))
        path.addQuadCurve(to: point(19, 450), control: point(31, 458))
        path.addQuadCurve(to: point(0, 422), control: point(4, 441))
        path.closeSubpath()

        path.move(to: point(260, 433))
        path.addLine(to: point(396, 433))
        path.addLine(to: point(392, 447))
        path.addQuadCurve(to: point(380, 452), control: point(389, 452))
        path.addLine(to: point(276, 452))
        path.addQuadCurve(to: point(264, 447), control: point(267, 452))
        path.closeSubpath()

        return path
    }
}

struct MacWallMenuBarBrandIcon: View {
    var body: some View {
        MacWallMenuBarMark()
            .fill(.primary, style: FillStyle(eoFill: true))
            .aspectRatio(656.0 / 458.0, contentMode: .fit)
            .frame(width: 18, height: 18)
    }
}
