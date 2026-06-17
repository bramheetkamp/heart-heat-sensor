import SwiftUI
import Charts

// MARK: - WorkoutView

/// Live view of the **always-on** heat-strain monitor. Heat warnings fire from
/// `BLEService` whenever the sensor is connected — even with the app closed and
/// no session started — so this screen is a *window* onto that monitoring, not
/// the on/off switch. It adds an optional session timer for convenience.
///
/// The view polls `BLEService` once a second via a ticker rather than observing
/// the nested object directly (it isn't re-broadcast through `AppEnvironment`).
struct WorkoutView: View {
    @EnvironmentObject private var env: AppEnvironment

    @State private var sessionStart: Date?
    @State private var now = Date()
    @State private var caution: Double = 38.5

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var assessment: HeatStrainEngine.Assessment { env.bleService.heatAssessment }
    private var trend: [HeatStrainEngine.Sample] { env.bleService.heatTrend }
    private var liveHR: Int? { env.bleService.latestHR?.heartRate }
    private var liveCore: Double? { env.bleService.latestTemp[.core]?.value }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                heatBanner
                statsRow
                if !trend.isEmpty { trendCard }
                sessionButton
                Label("Monitoring is always on while your sensor is connected — even with Pulse closed.",
                      systemImage: "bolt.shield.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if !env.bleService.isConnected {
                    Label("Connect your sensor (or turn on Demo Mode) to see live data.",
                          systemImage: "antenna.radiowaves.left.and.right.slash")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding()
        }
        .navigationTitle("Workout")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(ticker) { _ in now = Date() }
        .onAppear { caution = (try? env.dataStore.getOrCreateProfile().overheatingThreshold) ?? 38.5 }
    }

    // MARK: - Heat banner

    private var heatBanner: some View {
        let a = assessment
        return VStack(spacing: 12) {
            MascotView(state: a.level.mascotState, character: env.selectedCharacter, size: 84)
                .padding(.top, 4)
            Text(a.level.shortLabel.uppercased())
                .font(.caption.bold()).tracking(2)
                .foregroundStyle(.white.opacity(0.9))
            Text(a.title)
                .font(.title2.bold())
                .foregroundStyle(.white)
            Text(a.message)
                .font(.subheadline.weight(a.level >= .serious ? .semibold : .regular))
                .foregroundStyle(.white.opacity(0.95))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 18)
        .background(RoundedRectangle(cornerRadius: 24).fill(a.level.color.gradient))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.15), lineWidth: 1))
        .scaleEffect(a.level == .critical ? 1.015 : 1.0)
        .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                   value: a.level == .critical)
        .animation(.easeInOut(duration: 0.3), value: a.level)
    }

    // MARK: - Live stats

    private var statsRow: some View {
        HStack(spacing: 12) {
            statTile(title: "Heart Rate", value: liveHR.map { "\($0)" } ?? "—",
                     unit: "bpm", icon: "heart.fill", tint: .pink)
            statTile(title: "Core Temp", value: liveCore.map { String(format: "%.1f", $0) } ?? "—",
                     unit: "°C", icon: "thermometer.medium", tint: assessment.level.color)
            statTile(title: "Session", value: elapsedString, unit: "",
                     icon: "stopwatch", tint: .orange)
        }
    }

    private func statTile(title: String, value: String, unit: String, icon: String, tint: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(tint).font(.system(size: 16, weight: .semibold))
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.system(size: 22, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                if !unit.isEmpty { Text(unit).font(.caption2).foregroundStyle(.secondary) }
            }
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.quaternary, lineWidth: 1))
    }

    // MARK: - Trend

    private var trendCard: some View {
        let serious = HeatStrainEngine.seriousThreshold(caution: caution)
        let critical = HeatStrainEngine.criticalThreshold(caution: caution)
        let cores = trend.map(\.core)
        let lo = min((cores.min() ?? 36) - 0.3, caution - 0.5)
        let hi = max((cores.max() ?? 40) + 0.3, critical + 0.3)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Core temperature trend", systemImage: "chart.xyaxis.line")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                if let rate = assessment.riseRatePer10Min {
                    Text(String(format: "%+.1f °C/10 min", rate))
                        .font(.caption.bold())
                        .foregroundStyle(rate >= HeatStrainEngine.rapidRisePer10Min ? .red : .secondary)
                }
            }
            Chart {
                ForEach(Array(trend.enumerated()), id: \.offset) { _, s in
                    LineMark(x: .value("Time", s.time), y: .value("Core", s.core))
                        .foregroundStyle(assessment.level.color)
                        .interpolationMethod(.monotone)
                }
                RuleMark(y: .value("Serious", serious))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(.orange.opacity(0.7))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Serious").font(.caption2).foregroundStyle(.orange)
                    }
                RuleMark(y: .value("Critical", critical))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(.red.opacity(0.7))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Critical").font(.caption2).foregroundStyle(.red)
                    }
            }
            .chartYScale(domain: lo...hi)
            .chartXAxis(.hidden)
            .frame(height: 170)
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.quaternary, lineWidth: 1))
    }

    // MARK: - Optional session timer

    private var sessionButton: some View {
        Button {
            if sessionStart == nil { sessionStart = Date(); now = Date() } else { sessionStart = nil }
        } label: {
            Label(sessionStart == nil ? "Start Session Timer" : "End Session",
                  systemImage: sessionStart == nil ? "play.fill" : "stop.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .background(sessionStart == nil ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.red),
                    in: RoundedRectangle(cornerRadius: 16))
        .foregroundStyle(.white)
    }

    private var elapsedString: String {
        guard let sessionStart else { return "—" }
        let secs = max(0, Int(now.timeIntervalSince(sessionStart)))
        return String(format: "%d:%02d", secs / 60, secs % 60)
    }
}
