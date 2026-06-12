import SwiftUI

// MARK: - Mascot State

enum MascotState {
    case happy
    case sweating      // overheating
    case worried       // getting sick
    case sleepy        // poor recovery
    case cheering      // onboarding / milestone
    case scanning      // looking for device
    case neutral
}

// MARK: - MascotView

struct MascotView: View {
    let state: MascotState
    var size: CGFloat = 80

    @State private var bounceOffset: CGFloat = 0
    @State private var wiggleAngle: Double = 0
    @State private var blinkOpacity: Double = 1
    @State private var sweatDropOffset: CGFloat = 0
    @State private var sweatDropOpacity: Double = 0
    @State private var pulseScale: CGFloat = 1.0
    @State private var cheersOffset: CGFloat = 0
    @State private var scanRotation: Double = 0

    var body: some View {
        ZStack {
            bodyShape
            faceLayer
            stateAccessories
        }
        .frame(width: size, height: size)
        .onAppear { startAnimations() }
        .onChange(of: state) { startAnimations() }
    }

    // MARK: - Body

    private var bodyShape: some View {
        Circle()
            .fill(bodyGradient)
            .overlay(
                Circle()
                    .stroke(bodyStrokeColor, lineWidth: size * 0.025)
            )
            .scaleEffect(pulseScale)
            .offset(y: bounceOffset)
    }

    private var bodyGradient: RadialGradient {
        RadialGradient(
            colors: [bodyHighlight, bodyBaseColor],
            center: .init(x: 0.35, y: 0.3),
            startRadius: size * 0.05,
            endRadius: size * 0.55
        )
    }

    private var bodyBaseColor: Color {
        switch state {
        case .happy, .cheering: return Color(red: 1.0, green: 0.75, blue: 0.2)
        case .sweating:          return Color(red: 1.0, green: 0.45, blue: 0.2)
        case .worried:           return Color(red: 1.0, green: 0.65, blue: 0.3)
        case .sleepy:            return Color(red: 0.7, green: 0.7, blue: 0.9)
        case .scanning:          return Color(red: 0.4, green: 0.8, blue: 1.0)
        case .neutral:           return Color(red: 1.0, green: 0.82, blue: 0.4)
        }
    }

    private var bodyHighlight: Color { bodyBaseColor.opacity(0.4).blended(with: .white, fraction: 0.8) }
    private var bodyStrokeColor: Color { bodyBaseColor.opacity(0.6) }

    // MARK: - Face

    private var faceLayer: some View {
        ZStack {
            eyes
            mouth
        }
        .offset(y: bounceOffset)
    }

    private var eyes: some View {
        HStack(spacing: size * 0.15) {
            eyeShape
            eyeShape
        }
        .offset(y: -size * 0.08)
    }

    private var eyeShape: some View {
        ZStack {
            Capsule()
                .fill(Color.white)
                .frame(width: size * 0.17, height: size * 0.2 * blinkOpacity)
            Circle()
                .fill(Color(red: 0.15, green: 0.1, blue: 0.05))
                .frame(width: size * 0.09, height: size * 0.09 * blinkOpacity)
        }
        .rotationEffect(.degrees(wiggleAngle * 0.3))
    }

    @ViewBuilder
    private var mouth: some View {
        switch state {
        case .happy, .cheering, .neutral:
            smilingMouth
        case .sweating:
            pantingMouth
        case .worried:
            worriedMouth
        case .sleepy:
            sleepyMouth
        case .scanning:
            ohMouth
        }
    }

    private var smilingMouth: some View {
        Arc(startAngle: .degrees(20), endAngle: .degrees(160), clockwise: false)
            .stroke(Color(red: 0.3, green: 0.15, blue: 0.05), lineWidth: size * 0.035)
            .frame(width: size * 0.35, height: size * 0.2)
            .offset(y: size * 0.12)
    }

    private var pantingMouth: some View {
        Ellipse()
            .fill(Color(red: 0.8, green: 0.2, blue: 0.2))
            .overlay(
                Ellipse()
                    .fill(Color.pink.opacity(0.6))
                    .padding(size * 0.02)
            )
            .frame(width: size * 0.28, height: size * 0.18)
            .offset(y: size * 0.13)
    }

    private var worriedMouth: some View {
        Arc(startAngle: .degrees(20), endAngle: .degrees(160), clockwise: true)
            .stroke(Color(red: 0.3, green: 0.15, blue: 0.05), lineWidth: size * 0.035)
            .frame(width: size * 0.28, height: size * 0.14)
            .offset(y: size * 0.15)
    }

    private var sleepyMouth: some View {
        RoundedRectangle(cornerRadius: size * 0.04)
            .fill(Color(red: 0.3, green: 0.15, blue: 0.05).opacity(0.5))
            .frame(width: size * 0.25, height: size * 0.06)
            .offset(y: size * 0.15)
    }

    private var ohMouth: some View {
        Ellipse()
            .stroke(Color(red: 0.3, green: 0.15, blue: 0.05), lineWidth: size * 0.03)
            .frame(width: size * 0.15, height: size * 0.18)
            .offset(y: size * 0.13)
    }

    // MARK: - State Accessories

    @ViewBuilder
    private var stateAccessories: some View {
        switch state {
        case .sweating:
            sweatDrops
        case .sleepy:
            zzz
        case .cheering:
            sparkles
        case .scanning:
            scanRings
        case .worried:
            thermometerBadge
        default:
            EmptyView()
        }
    }

    private var sweatDrops: some View {
        ZStack {
            sweatDrop(offsetX: size * 0.45, offsetY: -size * 0.15, delay: 0)
            sweatDrop(offsetX: size * 0.38, offsetY: -size * 0.05, delay: 0.3)
        }
    }

    private func sweatDrop(offsetX: CGFloat, offsetY: CGFloat, delay: Double) -> some View {
        SweatDropShape()
            .fill(Color(red: 0.4, green: 0.7, blue: 1.0).opacity(0.85))
            .frame(width: size * 0.1, height: size * 0.14)
            .offset(x: offsetX, y: offsetY + sweatDropOffset)
            .opacity(sweatDropOpacity)
            .animation(.easeIn(duration: 0.8).repeatForever().delay(delay), value: sweatDropOffset)
    }

    private var zzz: some View {
        ZStack {
            Text("z").font(.system(size: size * 0.18, weight: .bold)).foregroundColor(.white.opacity(0.8))
                .offset(x: size * 0.35, y: -size * 0.25)
            Text("z").font(.system(size: size * 0.13, weight: .bold)).foregroundColor(.white.opacity(0.5))
                .offset(x: size * 0.44, y: -size * 0.38)
        }
        .offset(y: cheersOffset)
    }

    private var sparkles: some View {
        ZStack {
            SparkleShape().fill(Color.yellow)
                .frame(width: size * 0.15, height: size * 0.15)
                .offset(x: -size * 0.45, y: -size * 0.3)
                .rotationEffect(.degrees(scanRotation))
            SparkleShape().fill(Color.orange)
                .frame(width: size * 0.1, height: size * 0.1)
                .offset(x: size * 0.48, y: -size * 0.35)
                .rotationEffect(.degrees(-scanRotation))
            SparkleShape().fill(Color.yellow.opacity(0.7))
                .frame(width: size * 0.08, height: size * 0.08)
                .offset(x: size * 0.4, y: size * 0.3)
                .rotationEffect(.degrees(scanRotation * 1.5))
        }
    }

    private var scanRings: some View {
        ZStack {
            Circle()
                .stroke(Color.cyan.opacity(0.4), lineWidth: 2)
                .frame(width: size * 1.3, height: size * 1.3)
                .scaleEffect(pulseScale)
            Circle()
                .stroke(Color.cyan.opacity(0.2), lineWidth: 1.5)
                .frame(width: size * 1.6, height: size * 1.6)
                .scaleEffect(pulseScale * 0.9)
        }
    }

    private var thermometerBadge: some View {
        Image(systemName: "thermometer.medium")
            .font(.system(size: size * 0.22))
            .foregroundColor(.orange)
            .offset(x: size * 0.42, y: -size * 0.3)
            .rotationEffect(.degrees(wiggleAngle * 0.5))
    }

    // MARK: - Animations

    private func startAnimations() {
        stopAnimations()
        switch state {
        case .happy, .neutral:
            startBounce(intensity: 3, speed: 1.4)
            startBlink()
        case .sweating:
            startBounce(intensity: 2, speed: 0.8)
            startSweat()
            startWiggle()
        case .worried:
            startWiggle()
            startBlink(interval: 0.8)
        case .sleepy:
            startBounce(intensity: 1.5, speed: 2.5)
            startZFloat()
        case .cheering:
            startCheer()
            startSparkleRotation()
        case .scanning:
            startPulse()
            startScanAnimation()
        }
    }

    private func stopAnimations() {
        bounceOffset = 0
        wiggleAngle = 0
        blinkOpacity = 1
        sweatDropOffset = 0
        sweatDropOpacity = 0
        pulseScale = 1
        cheersOffset = 0
        scanRotation = 0
    }

    private func startBounce(intensity: CGFloat, speed: Double) {
        withAnimation(.easeInOut(duration: speed).repeatForever(autoreverses: true)) {
            bounceOffset = -intensity
        }
    }

    private func startBlink(interval: Double = 3.0) {
        Task {
            while true {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                withAnimation(.easeInOut(duration: 0.08)) { blinkOpacity = 0.05 }
                try? await Task.sleep(nanoseconds: 120_000_000)
                withAnimation(.easeInOut(duration: 0.08)) { blinkOpacity = 1 }
            }
        }
    }

    private func startWiggle() {
        withAnimation(.easeInOut(duration: 0.3).repeatForever(autoreverses: true)) {
            wiggleAngle = 8
        }
    }

    private func startSweat() {
        withAnimation(.easeIn(duration: 1.0).repeatForever()) {
            sweatDropOffset = size * 0.3
            sweatDropOpacity = 1
        }
    }

    private func startZFloat() {
        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
            cheersOffset = -size * 0.1
        }
    }

    private func startCheer() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.5).repeatForever(autoreverses: true)) {
            bounceOffset = -size * 0.12
        }
    }

    private func startSparkleRotation() {
        withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
            scanRotation = 360
        }
    }

    private func startPulse() {
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
            pulseScale = 1.12
        }
    }

    private func startScanAnimation() {
        withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
            scanRotation = 360
        }
    }
}

// MARK: - Helper Shapes

private struct Arc: Shape {
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

private struct SweatDropShape: Shape {
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

private struct SparkleShape: Shape {
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

// MARK: - Color Extension

private extension Color {
    func blended(with other: Color, fraction: Double) -> Color {
        // Approximate blend for the highlight
        return other.opacity(fraction)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 24) {
        HStack(spacing: 16) {
            VStack {
                MascotView(state: .happy, size: 70)
                Text("Happy").font(.caption)
            }
            VStack {
                MascotView(state: .sweating, size: 70)
                Text("Sweating").font(.caption)
            }
            VStack {
                MascotView(state: .worried, size: 70)
                Text("Worried").font(.caption)
            }
        }
        HStack(spacing: 16) {
            VStack {
                MascotView(state: .sleepy, size: 70)
                Text("Sleepy").font(.caption)
            }
            VStack {
                MascotView(state: .cheering, size: 70)
                Text("Cheering").font(.caption)
            }
            VStack {
                MascotView(state: .scanning, size: 70)
                Text("Scanning").font(.caption)
            }
        }
    }
    .padding()
}
