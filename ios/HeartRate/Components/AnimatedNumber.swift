import SwiftUI

/// Smoothly animates between numeric values with a rolling‑ticker transition.
struct AnimatedNumber: View {
    let value: Double
    var format: String = "%.0f"
    var font: Font = .system(size: 48, weight: .bold, design: .rounded)
    var color: Color = .primary

    @State private var displayedValue: Double = 0
    @State private var previousValue: Double = 0
    @State private var animationPhase: CGFloat = 0

    private var formattedNew: String { String(format: format, value) }
    private var formattedOld: String { String(format: format, previousValue) }

    var body: some View {
        ZStack {
            Text(formattedOld)
                .font(font)
                .foregroundColor(color)
                .offset(y: animationPhase * -28)
                .opacity(1 - animationPhase)

            Text(formattedNew)
                .font(font)
                .foregroundColor(color)
                .offset(y: (1 - animationPhase) * 28)
                .opacity(animationPhase)
        }
        .clipped()
        .onChange(of: value) { newVal in
            previousValue = displayedValue
            displayedValue = newVal
            animationPhase = 0
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                animationPhase = 1
            }
        }
        .onAppear {
            displayedValue = value
            previousValue = value
            animationPhase = 1
        }
    }
}

/// Compact animated value + unit label, used in dashboard cards.
struct MetricDisplay: View {
    let value: Double?
    var format: String = "%.0f"
    var unit: String = ""
    var font: Font = .system(size: 42, weight: .bold, design: .rounded)
    var unitFont: Font = .system(size: 18, weight: .semibold)
    var color: Color = .primary
    var placeholderText: String = "--"

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 2) {
            if let v = value {
                AnimatedNumber(value: v, format: format, font: font, color: color)
            } else {
                Text(placeholderText)
                    .font(font)
                    .foregroundColor(color.opacity(0.35))
            }
            if !unit.isEmpty {
                Text(unit)
                    .font(unitFont)
                    .foregroundColor(color.opacity(0.6))
            }
        }
    }
}

#Preview {
    struct Demo: View {
        @State private var hr: Double = 72
        var body: some View {
            VStack(spacing: 32) {
                MetricDisplay(value: hr, unit: "bpm", color: .red)
                Button("Change") {
                    hr = Double.random(in: 55...120)
                }
            }
            .padding()
        }
    }
    return Demo()
}
