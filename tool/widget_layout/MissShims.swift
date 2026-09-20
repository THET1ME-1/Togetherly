// Заглушки, которых «Скучаю» просит сверх общих: сердце рисуется формой, а
// не картинкой, и её в стенде надо чем-то заменить.

import SwiftUI

struct HeartShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.move(to: CGPoint(x: w / 2, y: h))
        p.addCurve(to: CGPoint(x: 0, y: h * 0.32),
                   control1: CGPoint(x: w * 0.1, y: h * 0.75),
                   control2: CGPoint(x: 0, y: h * 0.55))
        p.addArc(center: CGPoint(x: w * 0.25, y: h * 0.32), radius: w * 0.25,
                 startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addArc(center: CGPoint(x: w * 0.75, y: h * 0.32), radius: w * 0.25,
                 startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addCurve(to: CGPoint(x: w / 2, y: h),
                   control1: CGPoint(x: w, y: h * 0.55),
                   control2: CGPoint(x: w * 0.9, y: h * 0.75))
        p.closeSubpath()
        return p
    }
}
