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
    var character: MascotCharacter = .blob
    var size: CGFloat = 80

    @State private var bounceOffset: CGFloat = 0
    @State private var wiggleAngle: Double = 0
    @State private var blinkOpacity: Double = 1
    @State private var sweatDropOffset: CGFloat = 0
    @State private var sweatDropOpacity: Double = 0
    @State private var pulseScale: CGFloat = 1.0
    @State private var cheersOffset: CGFloat = 0
    @State private var scanRotation: Double = 0
    /// The blink loop runs as an async Task; we keep a handle so it can be
    /// cancelled. Without this, every startAnimations() (each appear / state
    /// change) leaked a new infinite Task that never stopped.
    @State private var blinkTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            characterEars     // Behind body so ears "merge" into head
            bodyShape
            faceLayer
            stateAccessories
        }
        .frame(width: size, height: size)
        .onAppear { startAnimations() }
        .onChange(of: state) { startAnimations() }
        .onChange(of: character) { startAnimations() }
        .onDisappear { blinkTask?.cancel(); blinkTask = nil }
    }

    // MARK: - Character Ears / Head Features

    @ViewBuilder
    private var characterEars: some View {
        switch character {
        case .blob:
            EmptyView()
        case .bear:
            bearEars
        case .owl:
            owlTufts
        case .fox:
            foxEars
        }
    }

    private var bearEars: some View {
        ZStack {
            bearEar(atX: -size * 0.27)
            bearEar(atX:  size * 0.27)
        }
    }

    private func bearEar(atX x: CGFloat) -> some View {
        Circle()
            .fill(bodyGradient)
            .overlay(Circle().stroke(bodyStrokeColor, lineWidth: size * 0.025))
            .frame(width: size * 0.32, height: size * 0.32)
            .offset(x: x, y: -size * 0.42 + bounceOffset)
    }

    private var owlTufts: some View {
        ZStack {
            owlTuft(atX: -size * 0.18, rotation: -15)
            owlTuft(atX:  size * 0.18, rotation:  15)
        }
    }

    private func owlTuft(atX x: CGFloat, rotation: Double) -> some View {
        RoundedRectangle(cornerRadius: size * 0.05)
            .fill(bodyGradient)
            .overlay(RoundedRectangle(cornerRadius: size * 0.05).stroke(bodyStrokeColor, lineWidth: size * 0.02))
            .frame(width: size * 0.14, height: size * 0.24)
            .rotationEffect(.degrees(rotation))
            .offset(x: x, y: -size * 0.47 + bounceOffset)
    }

    private var foxEars: some View {
        ZStack {
            foxEar(atX: -size * 0.26, rotation: -18)
            foxEar(atX:  size * 0.26, rotation:  18)
        }
    }

    private func foxEar(atX x: CGFloat, rotation: Double) -> some View {
        FoxEarShape()
            .fill(bodyGradient)
            .overlay(FoxEarShape().stroke(bodyStrokeColor, lineWidth: size * 0.025))
            .frame(width: size * 0.22, height: size * 0.3)
            .rotationEffect(.degrees(rotation))
            .offset(x: x, y: -size * 0.44 + bounceOffset)
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
        case .happy, .neutral:
            // Character-specific base color for calm states
            switch character {
            case .blob:  return Color(red: 1.0,  green: 0.75, blue: 0.2)   // golden yellow
            case .bear:  return Color(red: 0.72, green: 0.45, blue: 0.2)   // warm brown
            case .owl:   return Color(red: 0.55, green: 0.5,  blue: 0.78)  // lavender
            case .fox:   return Color(red: 0.95, green: 0.45, blue: 0.15)  // burnt orange
            }
        case .cheering: return Color(red: 1.0, green: 0.75, blue: 0.2)
        case .sweating: return Color(red: 1.0, green: 0.45, blue: 0.2)
        case .worried:  return Color(red: 1.0, green: 0.65, blue: 0.3)
        case .sleepy:   return Color(red: 0.7, green: 0.7,  blue: 0.9)
        case .scanning: return Color(red: 0.4, green: 0.8,  blue: 1.0)
        }
    }

    private var bodyHighlight: Color { bodyBaseColor.opacity(0.4).blended(with: .white, fraction: 0.8) }
    private var bodyStrokeColor: Color { bodyBaseColor.opacity(0.6) }

    // MARK: - Face

    /// Faces are built from character-specific features (muzzle, nose/beak,
    /// eye shape & colour) layered over shared, state-driven expression pieces
    /// (mouth, eyebrows, cheeks). The result reads as a distinct animal rather
    /// than one generic face recoloured per character.
    private var faceLayer: some View {
        ZStack {
            muzzle           // tan/white snout patch or owl facial disc
            cheeks           // soft blush, behind the features
            mouth
            noseFeature      // bear/fox nose or owl beak, on top of the muzzle
            eyes
            eyebrows         // above the eyes, carries most of the emotion
        }
        .offset(y: bounceOffset)
    }

    // MARK: Muzzle / facial disc

    @ViewBuilder
    private var muzzle: some View {
        switch character {
        case .bear:
            Ellipse()
                .fill(Color(red: 0.93, green: 0.8, blue: 0.62))
                .frame(width: size * 0.44, height: size * 0.36)
                .offset(y: size * 0.15)
        case .fox:
            Ellipse()
                .fill(Color.white.opacity(0.95))
                .frame(width: size * 0.34, height: size * 0.42)
                .offset(y: size * 0.17)
        case .owl:
            // Two overlapping feathered discs framing the big eyes.
            ZStack {
                Ellipse()
                    .fill(Color.white.opacity(0.16))
                    .frame(width: size * 0.72, height: size * 0.64)
                Ellipse()
                    .stroke(Color.white.opacity(0.25), lineWidth: size * 0.012)
                    .frame(width: size * 0.5, height: size * 0.5)
            }
            .offset(y: -size * 0.02)
        case .blob:
            EmptyView()
        }
    }

    // MARK: Nose / beak

    @ViewBuilder
    private var noseFeature: some View {
        switch character {
        case .bear:
            Ellipse()
                .fill(Color(red: 0.2, green: 0.12, blue: 0.1))
                .overlay(
                    Ellipse()
                        .fill(Color.white.opacity(0.35))
                        .frame(width: size * 0.04, height: size * 0.03)
                        .offset(x: -size * 0.02, y: -size * 0.018)
                )
                .frame(width: size * 0.14, height: size * 0.1)
                .offset(y: size * 0.045)
        case .fox:
            FoxNoseShape()
                .fill(Color(red: 0.12, green: 0.08, blue: 0.07))
                .frame(width: size * 0.13, height: size * 0.11)
                .offset(y: size * 0.07)
        case .owl:
            beak
        case .blob:
            EmptyView()
        }
    }

    private var beak: some View {
        BeakShape()
            .fill(
                LinearGradient(
                    colors: [Color(red: 1.0, green: 0.82, blue: 0.32),
                             Color(red: 0.92, green: 0.55, blue: 0.12)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .frame(width: size * 0.16, height: size * 0.2)
            .offset(y: size * 0.1)
    }

    // MARK: Cheeks

    @ViewBuilder
    private var cheeks: some View {
        if character != .owl {
            HStack(spacing: size * 0.36) {
                cheek
                cheek
            }
            .offset(y: size * 0.05)
        }
    }

    private var cheek: some View {
        Circle()
            .fill(Color(red: 1.0, green: 0.45, blue: 0.45).opacity(cheekOpacity))
            .frame(width: size * 0.13, height: size * 0.13)
            .blur(radius: size * 0.025)
    }

    private var cheekOpacity: Double {
        switch state {
        case .happy, .cheering: return 0.5
        case .sweating:         return 0.65
        default:                return 0.22
        }
    }

    // MARK: Eyes

    private var eyes: some View {
        HStack(spacing: eyeSpacing) {
            eyeShape
            eyeShape
        }
        .offset(y: eyeVerticalOffset)
    }

    private var eyeVerticalOffset: CGFloat {
        character == .owl ? -size * 0.04 : -size * 0.07
    }

    private var eyeSpacing: CGFloat {
        switch character {
        case .owl:  return size * 0.04   // owl eyes sit close together
        case .fox:  return size * 0.1
        case .bear: return size * 0.16
        case .blob: return size * 0.13
        }
    }

    /// Per-character eye geometry & iris colour. A white sclera, coloured iris,
    /// black pupil and a small offset catchlight give the eyes depth.
    private struct EyeMetrics {
        var scleraW: CGFloat
        var scleraH: CGFloat
        var irisD: CGFloat
        var pupilD: CGFloat
        var catchD: CGFloat
        var iris: Color
    }

    private var eyeMetrics: EyeMetrics {
        switch character {
        case .blob:
            return EyeMetrics(scleraW: size * 0.2, scleraH: size * 0.22,
                              irisD: size * 0.13, pupilD: size * 0.075, catchD: size * 0.05,
                              iris: Color(red: 0.3, green: 0.22, blue: 0.15))
        case .bear:
            return EyeMetrics(scleraW: size * 0.12, scleraH: size * 0.13,
                              irisD: size * 0.12, pupilD: size * 0.08, catchD: size * 0.04,
                              iris: Color(red: 0.16, green: 0.1, blue: 0.07))
        case .owl:
            return EyeMetrics(scleraW: size * 0.3, scleraH: size * 0.32,
                              irisD: size * 0.24, pupilD: size * 0.14, catchD: size * 0.07,
                              iris: Color(red: 0.95, green: 0.62, blue: 0.12))
        case .fox:
            return EyeMetrics(scleraW: size * 0.18, scleraH: size * 0.14,
                              irisD: size * 0.11, pupilD: size * 0.07, catchD: size * 0.04,
                              iris: Color(red: 0.5, green: 0.32, blue: 0.08))
        }
    }

    private var eyeShape: some View {
        let m = eyeMetrics
        let irisDrop = m.scleraH * 0.04
        return ZStack {
            Ellipse()
                .fill(Color.white)
                .overlay(Ellipse().stroke(Color.black.opacity(0.08), lineWidth: size * 0.008))
                .frame(width: m.scleraW, height: m.scleraH)
            Circle()
                .fill(m.iris)
                .frame(width: m.irisD, height: m.irisD)
                .offset(y: irisDrop)
            Circle()
                .fill(Color.black)
                .frame(width: m.pupilD, height: m.pupilD)
                .offset(y: irisDrop)
            Circle()
                .fill(Color.white.opacity(0.95))
                .frame(width: m.catchD, height: m.catchD)
                .offset(x: -m.irisD * 0.22, y: -m.irisD * 0.22 + irisDrop)
        }
        // blinkOpacity squishes the eye for blinks; eyeOpenFactor keeps the
        // eyes half-lidded while sleepy.
        .scaleEffect(x: 1, y: max(0.04, blinkOpacity * eyeOpenFactor), anchor: .center)
        .rotationEffect(.degrees(wiggleAngle * 0.3))
    }

    private var eyeOpenFactor: CGFloat {
        state == .sleepy ? 0.4 : 1.0
    }

    // MARK: Eyebrows

    @ViewBuilder
    private var eyebrows: some View {
        if character != .owl {
            HStack(spacing: browSpacing) {
                brow(mirror: false)
                brow(mirror: true)
            }
            .offset(y: eyeVerticalOffset - eyeMetrics.scleraH * 0.72 + browDrop)
        }
    }

    private var browSpacing: CGFloat { eyeSpacing + eyeMetrics.scleraW * 0.2 }

    private func brow(mirror: Bool) -> some View {
        Capsule()
            .fill(Color(red: 0.3, green: 0.2, blue: 0.12).opacity(0.85))
            .frame(width: eyeMetrics.scleraW * 0.9, height: size * 0.028)
            .rotationEffect(.degrees(mirror ? -browAngle : browAngle))
    }

    /// Positive angle furrows the inner ends downward (tense); negative raises
    /// them (concerned). Mirrored on the right brow.
    private var browAngle: Double {
        switch state {
        case .worried:  return -16
        case .sweating: return 14
        case .sleepy:   return 10
        case .scanning: return -6
        default:        return -3
        }
    }

    private var browDrop: CGFloat {
        switch state {
        case .scanning, .cheering: return -size * 0.02
        case .sweating, .sleepy:   return size * 0.015
        default:                   return 0
        }
    }

    // MARK: Mouth

    @ViewBuilder
    private var mouth: some View {
        if character == .owl {
            EmptyView()   // the beak serves as the owl's mouth
        } else {
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
        blinkTask?.cancel()
        blinkTask = nil
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
        blinkTask?.cancel()
        blinkTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                if Task.isCancelled { break }
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

// MARK: - Color Extension

private extension Color {
    func blended(with other: Color, fraction: Double) -> Color {
        return other.opacity(fraction)
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: 32) {
            // All states for default blob character
            Text("Blobby (default)").font(.headline)
            HStack(spacing: 16) {
                ForEach([MascotState.happy, .sweating, .worried], id: \.hashValue) { s in
                    MascotView(state: s, character: .blob, size: 60)
                }
            }

            Divider()

            // All characters in happy state
            Text("Characters").font(.headline)
            HStack(spacing: 20) {
                ForEach(MascotCharacter.allCases, id: \.rawValue) { c in
                    VStack(spacing: 6) {
                        MascotView(state: .happy, character: c, size: 70)
                        Text(c.displayName).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            // Emotional states for bear
            Text("Bruno (Bear)").font(.headline)
            HStack(spacing: 16) {
                ForEach([MascotState.happy, .sweating, .sleepy], id: \.hashValue) { s in
                    MascotView(state: s, character: .bear, size: 60)
                }
            }
        }
        .padding()
    }
}
