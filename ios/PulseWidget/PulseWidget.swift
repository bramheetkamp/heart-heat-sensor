import WidgetKit
import SwiftUI

// MARK: - Shared Data

private let kAppGroup = "group.com.heartrate.app"
private let kCachedHR = "cachedHR"
private let kCachedCoreTemp = "cachedCoreTemp"
private let kCachedReadingAt = "cachedReadingAt"
private let kCachedRecoveryScore = "cachedRecoveryScore"

// MARK: - Entry

struct PulseEntry: TimelineEntry {
    let date: Date
    let heartRate: Int?
    let coreTemp: Double?
    let recoveryScore: Int?
    let lastUpdated: Date?

    var isStale: Bool {
        guard let last = lastUpdated else { return true }
        return Date().timeIntervalSince(last) > 2 * 3600
    }

    var hrDisplay: String {
        guard let hr = heartRate, !isStale else { return "—" }
        return "\(hr)"
    }

    var coreTempDisplay: String {
        guard let t = coreTemp, !isStale else { return "—" }
        return String(format: "%.1f", t)
    }

    var recoveryDisplay: String {
        guard let s = recoveryScore else { return "—" }
        return "\(s)"
    }

    var recoveryColor: Color {
        guard let s = recoveryScore else { return .gray }
        switch s {
        case 0..<45:  return .red
        case 45..<65: return .orange
        case 65..<82: return .green
        default:      return .teal
        }
    }

    var recoveryLabel: String {
        guard let s = recoveryScore else { return "NO DATA" }
        switch s {
        case 0..<45:  return "LOW"
        case 45..<65: return "FAIR"
        case 65..<82: return "GOOD"
        default:      return "EXCELLENT"
        }
    }

    var lastUpdatedDisplay: String {
        guard let last = lastUpdated else { return "No data yet" }
        if Date().timeIntervalSince(last) < 90 { return "Just now" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: last, relativeTo: Date())
    }

    static func fromSharedDefaults() -> PulseEntry {
        let ud = UserDefaults(suiteName: kAppGroup)
        let hr    = (ud?.integer(forKey: kCachedHR) ?? 0)
        let temp  = (ud?.double(forKey: kCachedCoreTemp) ?? 0)
        let ts    = ud?.double(forKey: kCachedReadingAt) ?? 0
        let score = (ud?.integer(forKey: kCachedRecoveryScore) ?? 0)
        return PulseEntry(
            date: Date(),
            heartRate:     hr    > 0 ? hr    : nil,
            coreTemp:      temp  > 0 ? temp  : nil,
            recoveryScore: score > 0 ? score : nil,
            lastUpdated:   ts    > 0 ? Date(timeIntervalSince1970: ts) : nil
        )
    }
}

// MARK: - Provider

struct PulseProvider: TimelineProvider {
    func placeholder(in context: Context) -> PulseEntry {
        PulseEntry(date: Date(), heartRate: 68, coreTemp: 36.8, recoveryScore: 74, lastUpdated: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (PulseEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : .fromSharedDefaults())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PulseEntry>) -> Void) {
        let entry = PulseEntry.fromSharedDefaults()
        let next  = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Small View

struct PulseSmallView: View {
    let entry: PulseEntry

    var body: some View {
        ZStack {
            // Background ring track
            Circle()
                .stroke(Color(.systemGray5), lineWidth: 9)

            // Filled arc
            if let score = entry.recoveryScore {
                Circle()
                    .trim(from: 0, to: CGFloat(score) / 100)
                    .stroke(
                        LinearGradient(
                            colors: [entry.recoveryColor.opacity(0.7), entry.recoveryColor],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 9, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }

            VStack(spacing: 1) {
                Image(systemName: "bolt.heart.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.purple)

                Text(entry.recoveryDisplay)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(entry.recoveryColor)
                    .minimumScaleFactor(0.6)

                Text(entry.recoveryLabel)
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)

                Divider()
                    .padding(.horizontal, 20)
                    .padding(.vertical, 4)

                HStack(spacing: 3) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.red)
                    Text(entry.hrDisplay)
                        .font(.system(size: 12, weight: .semibold))
                    Text("bpm")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .widgetURL(URL(string: "heartrate://dashboard"))
    }
}

// MARK: - Medium View

struct PulseMediumView: View {
    let entry: PulseEntry

    var body: some View {
        HStack(spacing: 18) {
            // Left: recovery score ring
            ZStack {
                Circle()
                    .stroke(Color(.systemGray5), lineWidth: 10)
                if let score = entry.recoveryScore {
                    Circle()
                        .trim(from: 0, to: CGFloat(score) / 100)
                        .stroke(
                            LinearGradient(
                                colors: [entry.recoveryColor.opacity(0.7), entry.recoveryColor],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                }
                VStack(spacing: 1) {
                    Text(entry.recoveryDisplay)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(entry.recoveryColor)
                    Text(entry.recoveryLabel)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                        .tracking(0.5)
                }
            }
            .frame(width: 92, height: 92)

            // Right: metrics + header
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.heart.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.purple)
                    Text("Pulse")
                        .font(.system(size: 13, weight: .bold))
                }
                .padding(.bottom, 8)

                metricRow(icon: "heart.fill",         iconColor: .red,    value: entry.hrDisplay,       unit: "bpm")
                    .padding(.bottom, 6)
                metricRow(icon: "thermometer.medium", iconColor: .orange,  value: entry.coreTempDisplay, unit: "°C")

                Spacer()

                Text(entry.lastUpdatedDisplay)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .widgetURL(URL(string: "heartrate://dashboard"))
    }

    private func metricRow(icon: String, iconColor: Color, value: String, unit: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(iconColor)
                .frame(width: 16)
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .monospacedDigit()
            Text(unit)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Entry View + Widget + Bundle

struct PulseWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PulseEntry

    var body: some View {
        switch family {
        case .systemMedium:
            PulseMediumView(entry: entry)
        default:
            PulseSmallView(entry: entry)
        }
    }
}

struct PulseWidget: Widget {
    let kind = "PulseWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PulseProvider()) { entry in
            PulseWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Pulse")
        .description("Heart rate and recovery score at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct PulseWidgetBundle: WidgetBundle {
    var body: some Widget {
        PulseWidget()
    }
}
