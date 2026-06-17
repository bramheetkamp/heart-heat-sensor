import SwiftUI

// Custom `Shape`s used by `MascotView` to draw character features and the
// state accessories (sweat drops, sparkles, beaks, ears). Kept here so the
// MascotView file stays focused on layout, color, and animation.

struct Arc: Shape {
    var startAngle: Angle
    var endAngle: Angle
    var clockwise: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: rect.width / 2,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: clockwise
        )
        return path
    }
}

struct SweatDropShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        path.move(to: CGPoint(x: w * 0.5, y: 0))
        path.addCurve(to: CGPoint(x: w, y: h * 0.65),
                      control1: CGPoint(x: w, y: h * 0.25),
                      control2: CGPoint(x: w, y: h * 0.5))
        path.addArc(center: CGPoint(x: w * 0.5, y: h * 0.65),
                    radius: w * 0.5,
                    startAngle: .degrees(0),
                    endAngle: .degrees(180),
                    clockwise: false)
        path.addCurve(to: CGPoint(x: w * 0.5, y: 0),
                      control1: CGPoint(x: 0, y: h * 0.5),
                      control2: CGPoint(x: 0, y: h * 0.25))
        return path
    }
}

struct SparkleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let points = 4
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerR = min(rect.width, rect.height) / 2
        let innerR = outerR * 0.38
        let angleStep = .pi * 2 / Double(points)
        for i in 0..<points {
            let outerAngle = Double(i) * angleStep - .pi / 2
            let innerAngle = outerAngle + angleStep / 2
            let outerPt = CGPoint(x: center.x + outerR * cos(outerAngle),
                                   y: center.y + outerR * sin(outerAngle))
            let innerPt = CGPoint(x: center.x + innerR * cos(innerAngle),
                                   y: center.y + innerR * sin(innerAngle))
            if i == 0 { path.move(to: outerPt) } else { path.addLine(to: outerPt) }
            path.addLine(to: innerPt)
        }
        path.closeSubpath()
        return path
    }
}

/// Pointed triangular ear shape for the fox character.
struct FoxEarShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: 0, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Small downward-pointing triangular nose for the fox.
struct FoxNoseShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: 0))
        path.addLine(to: CGPoint(x: 0, y: 0))
        path.closeSubpath()
        return path
    }
}

/// Curved downward beak for the owl.
struct BeakShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        path.move(to: CGPoint(x: w * 0.5, y: h))
        path.addQuadCurve(to: CGPoint(x: w, y: 0),
                          control: CGPoint(x: w * 0.92, y: h * 0.55))
        path.addLine(to: CGPoint(x: 0, y: 0))
        path.addQuadCurve(to: CGPoint(x: w * 0.5, y: h),
                          control: CGPoint(x: w * 0.08, y: h * 0.55))
        path.closeSubpath()
        return path
    }
}
