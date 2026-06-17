import SwiftUI

/// Dashboard card showing a 0-100 recovery score derived from HRV and resting
/// heart rate trends vs. the 30-day baseline. Higher is better.
///
/// Score algorithm:
///   HRV component  = clamp(recent_hrv / baseline_hrv,  0.5, 1.5)  — more HRV = better
///   HR  component  = clamp(baseline_hr / recent_hr,    0.5, 1.5)  — lower HR  = better
///   raw            = 0.6 * HRV_component + 0.4 * HR_component
///   score          = clamp(raw * 70, 0, 100)        → baseline ≈ 70 ("Good")
struct RecoveryScoreCard: View {
    let readings: [Reading]

    @State private var animatedScore: Double = 0

    private var result: RecoveryResult { RecoveryScoreCard.compute(readings: readings) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Recovery Score", systemImage: "bolt.heart.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.purple)

            switch result {
            case .noBaseline:
                noBaselineView
            case .score(let s, let hrv, let hr):
                scoreView(score: s, hrv: hrv, hr: hr)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
        .onChange(of: result) { _, new in
            if case .score(let s, _, _) = new {
                withAnimation(.easeOut(duration: 1.0)) { animatedScore = Double(s) }
            }
        }
        .onAppear {
            if case .score(let s, _, _) = result {
                withAnimation(.easeOut(duration: 1.0).delay(0.2)) { animatedScore = Double(s) }
            }
        }
    }

    // MARK: - Score view

    private func scoreView(score: Int, hrv: MetricPair?, hr: MetricPair?) -> some View {
        HStack(alignment: .center, spacing: 24) {
            scoreRing(score: score)

            VStack(alignment: .leading, spacing: 10) {
                if let hrv {
                    metricRow(
                        icon: "waveform", label: "HRV",
                        value: String(format: "%.0f ms", hrv.current),
                        delta: hrv.delta, higherIsBetter: true
                    )
                }
                if let hr {
                    metricRow(
                        icon: "heart.fill", label: "Resting HR",
                        value: String(format: "%.0f bpm", hr.current),
                        delta: hr.delta, higherIsBetter: false
                    )
                }
                if hrv == nil && hr == nil {
                    Text("Not enough resting data for component breakdown.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func scoreRing(score: Int) -> some View {
        ZStack {
            Circle()
                .stroke(Color(.systemGray5), lineWidth: 10)
            Circle()
                .trim(from: 0, to: CGFloat(animatedScore) / 100)
                .stroke(
                    LinearGradient(
                        colors: [scoreColor(score).opacity(0.7), scoreColor(score)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 1.0), value: animatedScore)

            VStack(spacing: 0) {
                Text("\(score)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(scoreColor(score))
                    .contentTransition(.numericText())
                Text(scoreLabel(score))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)
            }
        }
        .frame(width: 100, height: 100)
    }

    private func metricRow(icon: String, label: String, value: String, delta: Double, higherIsBetter: Bool) -> some View {
        let isGood = higherIsBetter ? delta >= 0 : delta <= 0
        let pct = Int(abs(delta) * 100)
        let sign = delta >= 0 ? "+" : "-"
        let arrowIcon = delta >= 0 ? "arrow.up" : "arrow.down"

        return HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold))
            HStack(spacing: 2) {
                Image(systemName: arrowIcon)
                    .font(.system(size: 9, weight: .bold))
                Text("\(sign)\(pct)%")
                    .font(.system(size: 10))
            }
            .foregroundStyle(isGood ? Color.green : Color.orange)
        }
    }

    // MARK: - No baseline view

    private var noBaselineView: some View {
        HStack(spacing: 14) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 28))
                .foregroundStyle(.secondary.opacity(0.4))
            VStack(alignment: .leading, spacing: 4) {
                Text("Building your baseline")
                    .font(.system(size: 14, weight: .semibold))
                Text("Recovery score appears after 14 days of resting-state data.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
            }
        }
    }

    // MARK: - Helpers

    private func scoreColor(_ s: Int) -> Color {
        switch s {
        case 0..<45:  return .red
        case 45..<65: return .orange
        case 65..<82: return .green
        default:      return .teal
        }
    }

    private func scoreLabel(_ s: Int) -> String {
        switch s {
        case 0..<45:  return "LOW"
        case 45..<65: return "FAIR"
        case 65..<82: return "GOOD"
        default:      return "EXCELLENT"
        }
    }

    // MARK: - Computation

    struct MetricPair: Equatable {
        let current: Double
        let baseline: Double
        var delta: Double { (current - baseline) / baseline }
    }

    enum RecoveryResult: Equatable {
        case noBaseline
        case score(Int, hrv: MetricPair?, hr: MetricPair?)
    }

    static func compute(readings: [Reading]) -> RecoveryResult {
        let resting = readings.filter { $0.activity == .rest || $0.activity == .sleep }
        guard resting.count >= 20 else { return .noBaseline }

        let hrv7  = avg(resting, days: 7,  \.rmssd)
        let hrv30 = avg(resting, days: 30, \.rmssd)
        let hr7   = hrAvg(resting, days: 7)
        let hr30  = hrAvg(resting, days: 30)

        let baselineExists = (hrv30 != nil || hr30 != nil)
        guard baselineExists else { return .noBaseline }

        var components: [Double] = []
        var weights: [Double] = []

        let hrvPair: MetricPair?
        if let r = hrv7, let b = hrv30, b > 0 {
            let ratio = min(max(r / b, 0.5), 1.5)
            components.append(ratio)
            weights.append(0.6)
            hrvPair = MetricPair(current: r, baseline: b)
        } else { hrvPair = nil }

        let hrPair: MetricPair?
        if let r = hr7, let b = hr30, b > 0 {
            let ratio = min(max(b / r, 0.5), 1.5)
            components.append(ratio)
            weights.append(0.4)
            hrPair = MetricPair(current: r, baseline: b)
        } else { hrPair = nil }

        guard !components.isEmpty else { return .noBaseline }

        let totalWeight = weights.reduce(0, +)
        let raw = zip(components, weights).reduce(0.0) { $0 + $1.0 * $1.1 } / totalWeight
        let score = min(max(Int(raw * 70), 0), 100)

        return .score(score, hrv: hrvPair, hr: hrPair)
    }

    private static func avg(_ readings: [Reading], days: Int, _ kp: KeyPath<Reading, Double?>) -> Double? {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let vals = readings.filter { $0.timestamp >= cutoff }.compactMap { $0[keyPath: kp] }
        guard !vals.isEmpty else { return nil }
        return vals.reduce(0, +) / Double(vals.count)
    }

    private static func hrAvg(_ readings: [Reading], days: Int) -> Double? {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let vals = readings.filter { $0.timestamp >= cutoff }.compactMap { $0.heartRate.map(Double.init) }
        guard !vals.isEmpty else { return nil }
        return vals.reduce(0, +) / Double(vals.count)
    }
}
