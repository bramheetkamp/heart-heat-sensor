import SwiftUI

/// Dashboard card showing a 0-100 sleep quality score derived from last night's
/// sleep readings (activity == .sleep, within the past 24 hours).
///
/// Score algorithm (weighted average of available components):
///   HR component   = clamp(rest_baseline_hr / sleep_hr, 0.7, 1.3)   — lower sleep HR = better
///   HRV component  = clamp(sleep_hrv / baseline_hrv, 0.7, 1.3)      — higher sleep HRV = better
///   Duration       = triangle: peak at 7.5 h, clamped 0.7–1.3
///   score          = clamp((raw − 0.7) / 0.6 × 100, 0, 100)
struct SleepQualityCard: View {
    let readings: [Reading]

    @State private var animatedScore: Double = 0

    private var result: SleepResult { SleepQualityCard.compute(readings: readings) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Sleep Quality", systemImage: "moon.stars.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.indigo)

            switch result {
            case .noData:
                noDataView
            case .score(let s, let hr, let hrv, let dur):
                scoreView(score: s, hr: hr, hrv: hrv, durationHours: dur)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
        .onChange(of: result) { _, new in
            if case .score(let s, _, _, _) = new {
                withAnimation(.easeOut(duration: 1.0)) { animatedScore = Double(s) }
            }
        }
        .onAppear {
            if case .score(let s, _, _, _) = result {
                withAnimation(.easeOut(duration: 1.0).delay(0.2)) { animatedScore = Double(s) }
            }
        }
    }

    // MARK: - Score view

    private func scoreView(score: Int, hr: Double?, hrv: Double?, durationHours: Double?) -> some View {
        HStack(alignment: .center, spacing: 24) {
            sleepRing(score: score)

            VStack(alignment: .leading, spacing: 10) {
                if let dur = durationHours {
                    metricRow(icon: "clock.fill",  label: "Duration",
                              value: String(format: "%.1f h", dur))
                }
                if let hr {
                    metricRow(icon: "heart.fill",  label: "Avg HR",
                              value: String(format: "%.0f bpm", hr))
                }
                if let hrv {
                    metricRow(icon: "waveform",    label: "Avg HRV",
                              value: String(format: "%.0f ms",  hrv))
                }
                if hr == nil && hrv == nil && durationHours == nil {
                    Text("Wear your sensor overnight for full breakdown.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func sleepRing(score: Int) -> some View {
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

    private func metricRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 6) {
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
        }
    }

    // MARK: - No data view

    private var noDataView: some View {
        HStack(spacing: 14) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 28))
                .foregroundStyle(.secondary.opacity(0.4))
            VStack(alignment: .leading, spacing: 4) {
                Text("No sleep data yet")
                    .font(.system(size: 14, weight: .semibold))
                Text("Wear your sensor overnight — Pulse will score your sleep once it has enough data.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
            }
        }
    }

    // MARK: - Helpers

    private func scoreColor(_ s: Int) -> Color {
        switch s {
        case 0..<40:  return .red
        case 40..<60: return .orange
        case 60..<80: return .blue
        default:      return .indigo
        }
    }

    private func scoreLabel(_ s: Int) -> String {
        switch s {
        case 0..<40:  return "POOR"
        case 40..<60: return "FAIR"
        case 60..<80: return "GOOD"
        default:      return "GREAT"
        }
    }

    // MARK: - Computation

    enum SleepResult: Equatable {
        case noData
        case score(Int, hr: Double?, hrv: Double?, durationHours: Double?)
    }

    static func compute(readings: [Reading]) -> SleepResult {
        let cutoff = Date().addingTimeInterval(-24 * 3600)
        let sleepReadings = readings
            .filter { $0.activity == .sleep && $0.timestamp >= cutoff }
            .sorted { $0.timestamp < $1.timestamp }

        guard sleepReadings.count >= 4 else { return .noData }

        let avgHR: Double? = {
            let vals = sleepReadings.compactMap { $0.heartRate.map(Double.init) }
            return vals.isEmpty ? nil : vals.reduce(0, +) / Double(vals.count)
        }()

        let avgHRV: Double? = {
            let vals = sleepReadings.compactMap { $0.rmssd }
            return vals.isEmpty ? nil : vals.reduce(0, +) / Double(vals.count)
        }()

        let durationHours: Double? = {
            guard let first = sleepReadings.first?.timestamp,
                  let last  = sleepReadings.last?.timestamp else { return nil }
            let dur = last.timeIntervalSince(first) / 3600
            return dur >= 0.5 ? dur : nil
        }()

        // 30-day resting baseline (excluding the sleep window being scored)
        let baselineCutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let baseline = readings.filter {
            $0.activity == .rest && $0.timestamp >= baselineCutoff && $0.timestamp < cutoff
        }

        var components: [Double] = []
        var weights:    [Double] = []

        // HR: lower sleep HR vs resting baseline = better recovery
        if let sHR = avgHR {
            let baseHRVals = baseline.compactMap { $0.heartRate.map(Double.init) }
            if !baseHRVals.isEmpty {
                let baseAvg = baseHRVals.reduce(0, +) / Double(baseHRVals.count)
                components.append(min(max(baseAvg / sHR, 0.7), 1.3))
                weights.append(0.3)
            }
        }

        // HRV: higher sleep HRV vs baseline = deeper sleep
        if let sHRV = avgHRV {
            let baseHRVVals = baseline.compactMap { $0.rmssd }
            if !baseHRVVals.isEmpty {
                let baseAvg = baseHRVVals.reduce(0, +) / Double(baseHRVVals.count)
                components.append(min(max(sHRV / baseAvg, 0.7), 1.3))
                weights.append(0.5)
            }
        }

        // Duration: triangle centred on 7.5 h, clamped to [0.7, 1.3]
        if let dur = durationHours {
            let durScore: Double
            if dur < 5        { durScore = 0.7 + (dur / 5) * 0.25 }
            else if dur <= 8  { durScore = 0.95 + ((dur - 5) / 3) * 0.35 }
            else              { durScore = max(1.3 - (dur - 8) * 0.1, 0.9) }
            components.append(durScore)
            weights.append(0.2)
        }

        guard !components.isEmpty else {
            return .score(50, hr: avgHR, hrv: avgHRV, durationHours: durationHours)
        }

        let totalWeight = weights.reduce(0, +)
        let raw = zip(components, weights).reduce(0.0) { $0 + $1.0 * $1.1 } / totalWeight
        let score = min(max(Int((raw - 0.7) / 0.6 * 100), 0), 100)

        return .score(score, hr: avgHR, hrv: avgHRV, durationHours: durationHours)
    }
}
