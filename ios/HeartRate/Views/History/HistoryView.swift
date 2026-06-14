import SwiftUI
import SwiftData
import Charts

struct HistoryView: View {
    @EnvironmentObject private var env: AppEnvironment
    let initialMetric: AppRoute.HistoryMetric

    @Query(sort: \Reading.timestamp) private var allReadings: [Reading]
    @State private var selectedMetric: AppRoute.HistoryMetric
    @State private var selectedRange: TimeRange = .week

    init(metric: AppRoute.HistoryMetric) {
        self.initialMetric = metric
        self._selectedMetric = State(initialValue: metric)
    }

    enum TimeRange: String, CaseIterable {
        case day = "24h"
        case week = "7d"
        case month = "30d"

        var days: Int {
            switch self { case .day: return 1; case .week: return 7; case .month: return 30 }
        }
    }

    private var filteredReadings: [Reading] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -selectedRange.days, to: Date())!
        return allReadings.filter { $0.timestamp >= cutoff }
    }

    private var baselineReadings: [Reading] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        return allReadings.filter { $0.timestamp >= cutoff && $0.activity == .rest }
    }

    var body: some View {
        VStack(spacing: 0) {
            metricPicker
                .padding(.horizontal)
                .padding(.top, 8)

            rangePicker
                .padding(.horizontal)
                .padding(.top, 8)

            ScrollView {
                VStack(spacing: 20) {
                    mainChartCard
                    statsRow
                    if selectedMetric == .heartRate || selectedMetric == .hrv {
                        baselineComparisonCard
                    }
                }
                .padding()
            }
        }
        .navigationTitle(selectedMetric.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Pickers

    private var metricPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AppRoute.HistoryMetric.allCases, id: \.self) { m in
                    Button {
                        withAnimation(.spring(response: 0.35)) { selectedMetric = m }
                    } label: {
                        Text(m.displayName)
                            .font(.system(size: 14, weight: .medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(selectedMetric == m ? m.color : Color(.secondarySystemBackground),
                                        in: Capsule())
                            .foregroundColor(selectedMetric == m ? .white : .primary)
                    }
                }
            }
        }
    }

    private var rangePicker: some View {
        Picker("Range", selection: $selectedRange) {
            ForEach(TimeRange.allCases, id: \.self) { r in
                Text(r.rawValue).tag(r)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Main Chart

    private var mainChartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(selectedMetric.displayName)
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                Text(currentValueLabel)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }

            if filteredReadings.isEmpty {
                emptyChartPlaceholder
            } else {
                mainChart
                    .frame(height: 200)
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
    }

    @ViewBuilder
    private var mainChart: some View {
        Chart {
            ForEach(sampledReadings, id: \.id) { reading in
                if let value = chartValue(reading) {
                    AreaMark(
                        x: .value("Time", reading.timestamp),
                        y: .value(selectedMetric.displayName, value)
                    )
                    .foregroundStyle(
                        .linearGradient(
                            colors: [selectedMetric.color.opacity(0.3), selectedMetric.color.opacity(0.02)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    LineMark(
                        x: .value("Time", reading.timestamp),
                        y: .value(selectedMetric.displayName, value)
                    )
                    .foregroundStyle(selectedMetric.color)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }
            }

            // Baseline reference line
            if let baseline = baselineValue {
                RuleMark(y: .value("Baseline", baseline))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .trailing) {
                        Text("Baseline")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: xAxisStride)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                AxisValueLabel(format: xAxisFormat)
                    .font(.system(size: 10))
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                AxisValueLabel()
                    .font(.system(size: 10))
            }
        }
    }

    private var emptyChartPlaceholder: some View {
        VStack(spacing: 8) {
            MascotView(state: .neutral, size: 50)
            Text("No data for this period")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 150)
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: 12) {
            StatBox(label: "Average", value: avgValueLabel, color: selectedMetric.color)
            StatBox(label: "Min", value: minValueLabel, color: .secondary)
            StatBox(label: "Max", value: maxValueLabel, color: .secondary)
        }
    }

    // MARK: - Baseline Comparison

    private var baselineComparisonCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("vs. Your Baseline")
                .font(.system(size: 15, weight: .semibold))

            if let baseline = baselineValue, let recent = recentAverage {
                let delta = recent - baseline
                let sign = delta >= 0 ? "+" : ""
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("30-day baseline")
                            .font(.caption).foregroundColor(.secondary)
                        Text(formatValue(baseline))
                            .font(.system(size: 20, weight: .bold))
                    }
                    Spacer()
                    Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .foregroundColor(abs(delta) > alertDelta ? .orange : .green)
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("7-day average")
                            .font(.caption).foregroundColor(.secondary)
                        Text("\(sign)\(formatValue(delta))")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(abs(delta) > alertDelta ? .orange : .green)
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
            } else {
                Text("Need at least 14 days of data to compute baseline.")
                    .font(.footnote).foregroundColor(.secondary)
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
    }

    // MARK: - Helpers

    private var sampledReadings: [Reading] {
        let readings = filteredReadings
        let maxPoints = 300
        guard readings.count > maxPoints else { return readings }
        let step = readings.count / maxPoints
        return stride(from: 0, to: readings.count, by: step).map { readings[$0] }
    }

    private func chartValue(_ reading: Reading) -> Double? {
        switch selectedMetric {
        case .heartRate: return reading.heartRate.map(Double.init)
        case .coreTemp:  return reading.tempCore
        case .skinTemp:  return reading.tempSkin
        case .hrv:       return reading.rmssd
        }
    }

    private var currentValueLabel: String {
        guard let last = filteredReadings.last else { return "--" }
        guard let v = chartValue(last) else { return "--" }
        return "\(formatValue(v)) \(selectedMetric.unit)"
    }

    private var avgValueLabel: String {
        let vals = filteredReadings.compactMap { chartValue($0) }
        guard !vals.isEmpty else { return "--" }
        return "\(formatValue(vals.reduce(0, +) / Double(vals.count))) \(selectedMetric.unit)"
    }

    private var minValueLabel: String {
        let vals = filteredReadings.compactMap { chartValue($0) }
        guard let m = vals.min() else { return "--" }
        return "\(formatValue(m)) \(selectedMetric.unit)"
    }

    private var maxValueLabel: String {
        let vals = filteredReadings.compactMap { chartValue($0) }
        guard let m = vals.max() else { return "--" }
        return "\(formatValue(m)) \(selectedMetric.unit)"
    }

    private var baselineValue: Double? {
        let vals = baselineReadings.compactMap { chartValue($0) }
        guard vals.count >= 50 else { return nil }
        return vals.reduce(0, +) / Double(vals.count)
    }

    private var recentAverage: Double? {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let recent = allReadings.filter { $0.timestamp >= cutoff && $0.activity == .rest }
        let vals = recent.compactMap { chartValue($0) }
        guard !vals.isEmpty else { return nil }
        return vals.reduce(0, +) / Double(vals.count)
    }

    private var alertDelta: Double {
        switch selectedMetric {
        case .heartRate: return 5
        case .coreTemp, .skinTemp: return 0.3
        case .hrv: return 10
        }
    }

    private func formatValue(_ v: Double) -> String {
        switch selectedMetric {
        case .heartRate, .hrv: return String(format: "%.0f", v)
        case .coreTemp, .skinTemp: return String(format: "%.1f", v)
        }
    }

    private var xAxisStride: Calendar.Component {
        switch selectedRange {
        case .day: return .hour
        case .week: return .day
        case .month: return .weekOfYear
        }
    }

    private var xAxisFormat: Date.FormatStyle {
        switch selectedRange {
        case .day: return .dateTime.hour()
        case .week: return .dateTime.weekday(.abbreviated)
        case .month: return .dateTime.month(.abbreviated).day()
        }
    }
}

// MARK: - Extensions

extension AppRoute.HistoryMetric {
    var displayName: String {
        switch self {
        case .heartRate: return "Heart Rate"
        case .coreTemp:  return "Core Temp"
        case .skinTemp:  return "Skin Temp"
        case .hrv:       return "HRV"
        }
    }

    var unit: String {
        switch self {
        case .heartRate: return "bpm"
        case .coreTemp, .skinTemp: return "°C"
        case .hrv: return "ms"
        }
    }

    var color: Color {
        switch self {
        case .heartRate: return .red
        case .coreTemp:  return .orange
        case .skinTemp:  return .yellow
        case .hrv:       return .purple
        }
    }

    static var allCases: [AppRoute.HistoryMetric] { [.heartRate, .coreTemp, .skinTemp, .hrv] }
}

// MARK: - Sub-components

private struct StatBox: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    NavigationStack {
        HistoryView(metric: .heartRate)
            .environmentObject(AppEnvironment())
    }
}
