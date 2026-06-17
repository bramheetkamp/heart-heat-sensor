import SwiftUI
import Charts
import UIKit

// MARK: - WorkoutView

/// Live training session screen. Shows real-time HR + core temperature, the
/// core-temp trend during the session, and an **escalating** heat-strain banner
/// powered by `HeatStrainEngine` — warning early (ease off), then harshly telling
/// the athlete to stop. Strong haptics + an interruptive notification fire as the
/// level rises into `serious`/`critical`.
struct WorkoutView: View {
    @EnvironmentObject private var env: AppEnvironment

    @State private var isRunning = false
    @State private var startTime: Date?
    @State private var now = Date()
    @State private var samples: [HeatStrainEngine.Sample] = []
    @State private var peakLevel: HeatStrainEngine.Level = .nominal
    @State private var caution: Double = 38.5

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let impact = UIImpactFeedbackGenerator(style: .heavy)
    private let notify = UINotificationFeedbackGenerator()

    /// Keep at most 30 min of 1 Hz samples to bound memory on long sessions.
    private static let maxSamples = 1_800

    private var assessment: HeatStrainEngine.Assessment {
        HeatStrainEngine.assess(samples: samples, isActive: isRunning, caution: caution, now: now)
    }

    private var liveHR: Int? { env.bleService.latestHR?.heartRate }
    private var liveCore: Double? { env.bleService.latestTemp[.core]?.value }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                heatBanner
                statsRow
                if !samples.isEmpty { trendCard }
                controlButton
                if !env.bleService.isConnected {
                    Label("Connect your sensor (or turn on Demo Mode) to see live data.",
                          systemImage: "antenna.radiowaves.left.and.right.slash")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
            }
            .padding()
        }
        .navigationTitle("Workout")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(ticker) { _ in tick() }
        .onAppear {
            caution = (try? env.dataStore.getOrCreateProfile().overheatingThreshold) ?? 38.5
            impact.prepare(); notify.prepare()
        }
        .onDisappear { if isRunning { stop() } }
    }

    // MARK: - Heat banner

    private var heatBanner: some View {
        let a = assessment
        return VStack(spacing: 12) {
            MascotView(state: a.level.mascotState, character: env.selectedCharacter, size: 84)
                .padding(.top, 4)
            Text(a.level.shortLabel.uppercased())
                .font(.caption.bold())
                .tracking(2)
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
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(a.level.color.gradient)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(.white.opacity(0.15), lineWidth: 1)
        )
        // Pulse the critical banner to demand attention.
        .scaleEffect(a.level == .critical && isRunning ? 1.015 : 1.0)
        .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                   value: a.level == .critical && isRunning)
        .animation(.easeInOut(duration: 0.3), value: a.level)
    }

    // MARK: - Live stats

    private var statsRow: some View {
        HStack(spacing: 12) {
            statTile(title: "Heart Rate",
                     value: liveHR.map { "\($0)" } ?? "—",
                     unit: "bpm",
                     icon: "heart.fill",
                     tint: .pink)
            statTile(title: "Core Temp",
                     value: liveCore.map { String(format: "%.1f", $0) } ?? "—",
                     unit: "°C",
                     icon: "thermometer.medium",
                     tint: assessment.level.color)
            statTile(title: "Elapsed",
                     value: elapsedString,
                     unit: "",
                     icon: "stopwatch",
                     tint: .orange)
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
        let cores = samples.map(\.core)
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
                ForEach(Array(samples.enumerated()), id: \.offset) { _, s in
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

    // MARK: - Control

    private var controlButton: some View {
        Button {
            isRunning ? stop() : start()
        } label: {
            Label(isRunning ? "End Workout" : "Start Workout",
                  systemImage: isRunning ? "stop.fill" : "play.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .background(isRunning ? AnyShapeStyle(.red) : AnyShapeStyle(Color.orange),
                    in: RoundedRectangle(cornerRadius: 16))
        .foregroundStyle(.white)
    }

    // MARK: - Session control

    private func start() {
        isRunning = true
        startTime = Date()
        now = Date()
        samples = []
        peakLevel = .nominal
        env.notifications.resetHeatStrainAlerts()
        impact.prepare(); notify.prepare()
        notify.notificationOccurred(.success)
    }

    private func stop() {
        isRunning = false
        env.notifications.resetHeatStrainAlerts()
    }

    private func tick() {
        guard isRunning else { return }
        now = Date()
        if let core = liveCore {
            samples.append(.init(time: now, core: core))
            if samples.count > Self.maxSamples {
                samples.removeFirst(samples.count - Self.maxSamples)
            }
        }
        let a = assessment

        // Escalation feedback: haptic when crossing into a new, higher level…
        if a.level > peakLevel {
            peakLevel = a.level
            switch a.level {
            case .critical: notify.notificationOccurred(.error)
            case .serious:  notify.notificationOccurred(.warning)
            case .elevated: impact.impactOccurred()
            case .nominal:  break
            }
        }
        // …and a continuous heavy buzz while critical, so it's impossible to ignore.
        if a.level == .critical { impact.impactOccurred(intensity: 1.0) }

        // notifyHeatStrain self-throttles (only re-fires on a higher level).
        Task { await env.notifications.notifyHeatStrain(level: a.level, message: a.message) }
    }

    private var elapsedString: String {
        guard let startTime else { return "0:00" }
        let secs = max(0, Int(now.timeIntervalSince(startTime)))
        return String(format: "%d:%02d", secs / 60, secs % 60)
    }
}
