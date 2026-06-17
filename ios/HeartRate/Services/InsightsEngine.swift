import Foundation

// MARK: - Insight

struct Insight: Identifiable {
    let id = UUID()
    let systemImage: String
    let level: Level
    let text: String

    enum Level { case good, caution, alert, neutral }
}

// MARK: - InsightsEngine

/// Pure rule-based engine that turns biometric readings into a ranked list of
/// plain-language insights. Used as the fallback on devices without Apple
/// Intelligence (iOS < 26 or AI not enabled). No SwiftUI dependency.
struct InsightsEngine {

    // MARK: - Public API

    /// Returns up to `maxCount` ranked insights, most important first.
    static func generate(
        readings: [Reading],
        warnings: [HealthWarning],
        maxCount: Int = 3
    ) -> [Insight] {
        guard !readings.isEmpty else {
            return [Insight(
                systemImage: "chart.line.uptrend.xyaxis",
                level: .neutral,
                text: "Keep wearing your sensor to build baselines. Personalised insights appear after a few days of data."
            )]
        }

        var result: [(priority: Int, insight: Insight)] = []

        // 1. Active warnings (highest priority)
        for w in warnings.prefix(1) where w.resolvedAt == nil {
            result.append((8, Insight(systemImage: w.type.icon, level: .alert, text: w.message)))
        }

        // 2. Heart-rate trend vs. 30-day baseline
        let resting = readings.filter { $0.activity == .rest || $0.activity == .sleep }
        if let recent = hrAvg(resting, days: 7), let base = hrAvg(resting, days: 30), base > 0 {
            let pct = (recent - base) / base * 100
            if pct < -5 {
                result.append((6, Insight(
                    systemImage: "heart.fill", level: .good,
                    text: "Resting HR is \(Int(abs(pct)))% lower this week vs. your 30-day average — a healthy downward trend."
                )))
            } else if pct > 8 {
                result.append((6, Insight(
                    systemImage: "heart.fill", level: .caution,
                    text: "Resting HR is up \(Int(pct))% above baseline this week. That can follow illness, stress, or poor sleep."
                )))
            } else {
                result.append((2, Insight(
                    systemImage: "heart.fill", level: .neutral,
                    text: "Resting heart rate is stable — right in line with your 30-day average."
                )))
            }
        }

        // 3. HRV trend
        if let recent = dblAvg(resting, days: 7, \.rmssd),
           let base = dblAvg(resting, days: 30, \.rmssd), base > 0 {
            let pct = (recent - base) / base * 100
            if pct > 10 {
                result.append((5, Insight(
                    systemImage: "waveform", level: .good,
                    text: "HRV is up \(Int(pct))% compared to baseline — your nervous system is recovering well."
                )))
            } else if pct < -15 {
                result.append((5, Insight(
                    systemImage: "waveform", level: .caution,
                    text: "HRV has dipped \(Int(abs(pct)))% below baseline. Prioritising rest and sleep tonight can help."
                )))
            }
        }

        // 4. Core temperature 3-day average
        if let recentTemp = dblAvg(resting, days: 3, \.tempCore), recentTemp >= 38.0 {
            result.append((7, Insight(
                systemImage: "thermometer.medium", level: .alert,
                text: "3-day average core temperature is \(String(format: "%.1f", recentTemp))°C, slightly elevated. Stay hydrated and monitor the trend."
            )))
        }

        // 5. Positive temperature note
        if let recentTemp = dblAvg(resting, days: 7, \.tempCore),
           let baseTemp  = dblAvg(resting, days: 30, \.tempCore),
           abs(recentTemp - baseTemp) < 0.2, recentTemp < 37.5 {
            result.append((1, Insight(
                systemImage: "thermometer.sun", level: .good,
                text: "Core temperature has been steady and within normal range all week."
            )))
        }

        // 6. Data-consistency praise (only when streak is ≥ 3 and no other good news)
        let uniqueDays = uniqueReadingDays(readings)
        if uniqueDays >= 7 {
            result.append((3, Insight(
                systemImage: "flame.fill", level: .good,
                text: "\(uniqueDays) days of data so far — baselines are becoming more accurate."
            )))
        }

        // Sort by priority desc, deduplicate same systemImage, take top N
        let sorted = result.sorted { $0.priority > $1.priority }.map(\.insight)
        var seen = Set<String>()
        var final: [Insight] = []
        for insight in sorted {
            guard !seen.contains(insight.systemImage) else { continue }
            seen.insert(insight.systemImage)
            final.append(insight)
            if final.count == maxCount { break }
        }
        return final.isEmpty ? [Insight(systemImage: "checkmark.circle", level: .neutral,
                                         text: "Everything looks normal based on your recent readings.")] : final
    }

    // MARK: - Private helpers

    private static func hrAvg(_ readings: [Reading], days: Int) -> Double? {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let vals = readings.filter { $0.timestamp >= cutoff }.compactMap { $0.heartRate.map(Double.init) }
        guard !vals.isEmpty else { return nil }
        return vals.reduce(0, +) / Double(vals.count)
    }

    private static func dblAvg(_ readings: [Reading], days: Int, _ kp: KeyPath<Reading, Double?>) -> Double? {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let vals = readings.filter { $0.timestamp >= cutoff }.compactMap { $0[keyPath: kp] }
        guard !vals.isEmpty else { return nil }
        return vals.reduce(0, +) / Double(vals.count)
    }

    private static func uniqueReadingDays(_ readings: [Reading]) -> Int {
        Set(readings.map { Calendar.current.startOfDay(for: $0.timestamp) }).count
    }
}
