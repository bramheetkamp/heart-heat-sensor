import SwiftUI
import Charts

struct WeeklyTrendCard: View {
    let readings: [Reading]

    struct DayPoint: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
    }

    private var resting: [Reading] {
        readings.filter { $0.activity == .rest || $0.activity == .sleep }
    }

    private func dailyPoints(extract: (Reading) -> Double?) -> [DayPoint] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<7).reversed().compactMap { offset -> DayPoint? in
            guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let next = cal.date(byAdding: .day, value: 1, to: day)!
            let vals = resting
                .filter { $0.timestamp >= day && $0.timestamp < next }
                .compactMap(extract)
            guard !vals.isEmpty else { return nil }
            return DayPoint(date: day, value: vals.reduce(0, +) / Double(vals.count))
        }
    }

    private func deltaVsAvg(_ points: [DayPoint]) -> Double? {
        guard points.count >= 2, let latest = points.last else { return nil }
        let prior = Array(points.dropLast())
        let avg = prior.map(\.value).reduce(0, +) / Double(prior.count)
        guard avg > 0 else { return nil }
        return (latest.value - avg) / avg
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Weekly Trends", systemImage: "chart.line.uptrend.xyaxis")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.blue)

            let hrvPoints = dailyPoints { $0.rmssd }
            let hrPoints  = dailyPoints { $0.heartRate.map(Double.init) }

            if hrvPoints.isEmpty && hrPoints.isEmpty {
                noDataView
            } else {
                HStack(alignment: .top, spacing: 16) {
                    if !hrvPoints.isEmpty {
                        trendColumn(
                            title: "HRV", points: hrvPoints,
                            unit: "ms", color: .purple, higherIsBetter: true
                        )
                    }
                    if !hrPoints.isEmpty {
                        trendColumn(
                            title: "Resting HR", points: hrPoints,
                            unit: "bpm", color: .red, higherIsBetter: false
                        )
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
    }

    private func trendColumn(
        title: String, points: [DayPoint],
        unit: String, color: Color, higherIsBetter: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let delta = deltaVsAvg(points) {
                    let isGood = higherIsBetter ? delta >= 0 : delta <= 0
                    let pct = Int(abs(delta) * 100)
                    let sign = delta >= 0 ? "+" : "-"
                    Text("\(sign)\(pct)%")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isGood ? Color.green : Color.orange)
                }
            }

            if let latest = points.last {
                Text(String(format: "%.0f \(unit)", latest.value))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
            }

            let minV = points.map(\.value).min() ?? 0
            let maxV = points.map(\.value).max() ?? 1
            let pad  = max((maxV - minV) * 0.3, 1)

            Chart {
                if points.count > 1 {
                    ForEach(points) { pt in
                        AreaMark(
                            x: .value("Day", pt.date),
                            y: .value("Value", pt.value)
                        )
                        .foregroundStyle(LinearGradient(
                            colors: [color.opacity(0.25), color.opacity(0.02)],
                            startPoint: .top, endPoint: .bottom
                        ))
                        .interpolationMethod(.catmullRom)
                    }
                    ForEach(points) { pt in
                        LineMark(
                            x: .value("Day", pt.date),
                            y: .value("Value", pt.value)
                        )
                        .foregroundStyle(color)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.catmullRom)
                    }
                } else {
                    ForEach(points) { pt in
                        PointMark(
                            x: .value("Day", pt.date),
                            y: .value("Value", pt.value)
                        )
                        .symbolSize(36)
                        .foregroundStyle(color)
                    }
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: (minV - pad)...(maxV + pad))
            .frame(height: 56)
            // catmullRom interpolation can overshoot the Y-domain, and a Chart
            // doesn't clip to its frame by default — without this the area fill
            // (e.g. the red Resting-HR mark) spills outside the card and draws
            // over the metric grid below it.
            .clipped()
        }
        .frame(maxWidth: .infinity)
    }

    private var noDataView: some View {
        HStack(spacing: 14) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 26))
                .foregroundStyle(.secondary.opacity(0.4))
            VStack(alignment: .leading, spacing: 4) {
                Text("Not enough data yet")
                    .font(.system(size: 14, weight: .semibold))
                Text("Weekly trends appear once you have resting-state readings across multiple days.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
            }
        }
    }
}
