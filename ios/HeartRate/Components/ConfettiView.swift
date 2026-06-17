import SwiftUI

// MARK: - Confetti Overlay

/// Full-screen confetti burst shown when the user earns an excellent recovery score.
/// Purely SwiftUI — no external dependencies required.
struct ConfettiOverlay: View {
    @Binding var isActive: Bool

    @State private var pieces: [ConfettiPiece] = []
    @State private var falling = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(pieces) { piece in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(piece.color)
                        .frame(width: piece.width, height: piece.height)
                        .position(
                            x: piece.xFraction * geo.size.width,
                            y: falling ? geo.size.height + 60 : -30
                        )
                        .rotationEffect(.degrees(falling ? piece.endAngle : piece.startAngle))
                        .animation(
                            .linear(duration: piece.duration).delay(piece.delay),
                            value: falling
                        )
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            if isActive { trigger() }
        }
        .onChange(of: isActive) { _, active in
            if active { trigger() }
        }
    }

    private func trigger() {
        pieces = (0..<90).map { _ in .random() }
        falling = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation { falling = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.8) {
            isActive = false
            pieces = []
            falling = false
        }
    }
}

// MARK: - Confetti Piece Model

private struct ConfettiPiece: Identifiable {
    let id = UUID()
    let xFraction: Double
    let color: Color
    let width: Double
    let height: Double
    let startAngle: Double
    let endAngle: Double
    let duration: Double
    let delay: Double

    static func random() -> ConfettiPiece {
        let palette: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .pink, .teal, .mint, .cyan]
        return ConfettiPiece(
            xFraction: Double.random(in: 0.02...0.98),
            color: palette.randomElement()!,
            width: Double.random(in: 6...13),
            height: Double.random(in: 10...18),
            startAngle: Double.random(in: 0...180),
            endAngle: Double.random(in: 360...900),
            duration: Double.random(in: 2.0...3.5),
            delay: Double.random(in: 0...1.3)
        )
    }
}
