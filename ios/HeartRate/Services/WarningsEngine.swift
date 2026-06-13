import Foundation

// MARK: - WarningsEngine

/// Pure computation engine for deriving HealthWarnings from stored Readings.
/// All methods are static — no mutable state.
struct WarningsEngine {

    // MARK: - Minimum Data Requirements

    /// Minimum days of data needed before sick/fatigue baselines are meaningful.
    private static let minimumBaselineDays = 14

    // MARK: - Entry Point

    /// Compute all applicable warnings for the given readings and user profile.
    static func compute(readings: [Reading], profile: UserProfile) -> [HealthWarning] {
        var warnings: [HealthWarning] = []
        if let w = checkOverheating(readings: readings, profile: profile) { warnings.append(w) }
        if let w = checkGettingSick(readings: readings, profile: profile) { warnings.append(w) }
        if let w = checkFatigue(readings: readings, profile: profile) { warnings.append(w) }
        return warnings
    }

    // MARK: - Overheating

    /// Fires when:
    ///  - Any reading in the past 24 hours has tempCore > profile.overheatingThreshold, OR
    ///  - tempCore rose more than 1.0 °C within any 30-minute window in the past 24 hours.
    static func checkOverheating(readings: [Reading], profile: UserProfile) -> HealthWarning? {
        let cutoff = Date().addingTimeInterval(-86_400)
        let recent = readings.filter { $0.timestamp >= cutoff && $0.tempCore != nil }
            .sorted { $0.timestamp < $1.timestamp }
        guard !recent.isEmpty else { return nil }

        // Absolute threshold check
        if let hotReading = recent.first(where: { ($0.tempCore ?? 0) > profile.overheatingThreshold }) {
            let temp = hotReading.tempCore!
            return HealthWarning(
                id: UUID(),
                type: .overheating,
                firedAt: Date(),
                resolvedAt: nil,
                title: "Overheating Alert",
                message: String(format: "Your core temperature reached %.1f °C, above the %.1f °C threshold.", temp, profile.overheatingThreshold),
                context: HealthWarning.WarningContext(
                    triggerValues: ["tempCore": temp],
                    baselineValues: ["threshold": profile.overheatingThreshold],
                    trendValues: recent.compactMap(\.tempCore),
                    explanation: "Core temperature exceeded the configured overheating threshold."
                ),
                deepLinkPath: "/warnings/overheating"
            )
        }

        // 30-minute window rapid-rise check (>1.0 °C)
        let windowSeconds: TimeInterval = 1_800
        for i in 0 ..< recent.count {
            let base = recent[i]
            guard let baseTemp = base.tempCore else { continue }
            for j in (i + 1) ..< recent.count {
                let later = recent[j]
                guard later.timestamp.timeIntervalSince(base.timestamp) <= windowSeconds else { break }
                guard let laterTemp = later.tempCore else { continue }
                let rise = laterTemp - baseTemp
                if rise > 1.0 {
                    return HealthWarning(
                        id: UUID(),
                        type: .overheating,
                        firedAt: Date(),
                        resolvedAt: nil,
                        title: "Rapid Temperature Rise",
                        message: String(format: "Core temperature rose %.1f °C in under 30 minutes.", rise),
                        context: HealthWarning.WarningContext(
                            triggerValues: ["rise": rise, "fromTemp": baseTemp, "toTemp": laterTemp],
                            baselineValues: ["maxAllowedRise": 1.0],
                            trendValues: recent.compactMap(\.tempCore),
                            explanation: "A rapid rise in core temperature was detected over a short time window."
                        ),
                        deepLinkPath: "/warnings/overheating"
                    )
                }
            }
        }

        return nil
    }

    // MARK: - Getting Sick

    /// Fires when the 7-day average resting HR OR temperature is elevated
    /// above the 30-day rolling baseline by the configured thresholds,
    /// and this has persisted for at least 2 consecutive days.
    ///
    /// Returns nil if fewer than `minimumBaselineDays` of data are available.
    static func checkGettingSick(readings: [Reading], profile: UserProfile) -> HealthWarning? {
        let sorted = readings.sorted { $0.timestamp < $1.timestamp }
        guard hasEnoughHistory(sorted, days: minimumBaselineDays) else { return nil }

        let resting = restingReadings(sorted)
        guard !resting.isEmpty else { return nil }

        // 30-day baseline
        let hrBaseline  = rollingAverage(readings: resting, days: 30, keyPath: \.heartRateDouble)
        let tmpBaseline = rollingAverage(readings: resting, days: 30, keyPath: \.tempCore)
        guard let hrBaseline, let tmpBaseline else { return nil }

        // Check each of the last 2 days individually to detect sustained elevation
        let calendar = Calendar.current
        var elevatedDays = 0

        for dayOffset in 1...7 {
            guard let dayStart = calendar.date(byAdding: .day, value: -dayOffset, to: startOfToday()),
                  let dayEnd   = calendar.date(byAdding: .day, value:  1, to: dayStart) else { continue }

            let dayReadings = resting.filter { $0.timestamp >= dayStart && $0.timestamp < dayEnd }
            guard dayReadings.count >= 3 else { continue }

            let dayHR   = dayReadings.compactMap(\.heartRateDouble).average
            let dayTemp = dayReadings.compactMap(\.tempCore).average

            let hrElevated   = (dayHR  - hrBaseline)  >= profile.sickHRThreshold
            let tempElevated = (dayTemp - tmpBaseline) >= profile.sickTempThreshold

            if hrElevated || tempElevated {
                elevatedDays += 1
            }
        }

        guard elevatedDays >= 2 else { return nil }

        let recentHR   = rollingAverage(readings: resting, days: 7, keyPath: \.heartRateDouble) ?? hrBaseline
        let recentTemp = rollingAverage(readings: resting, days: 7, keyPath: \.tempCore) ?? tmpBaseline

        return HealthWarning(
            id: UUID(),
            type: .gettingSick,
            firedAt: Date(),
            resolvedAt: nil,
            title: "You May Be Getting Sick",
            message: "Your resting heart rate and temperature have been elevated for \(elevatedDays) days compared to your 30-day baseline.",
            context: HealthWarning.WarningContext(
                triggerValues: ["avgHR": recentHR, "avgTemp": recentTemp, "elevatedDays": Double(elevatedDays)],
                baselineValues: ["hrBaseline": hrBaseline, "tempBaseline": tmpBaseline],
                trendValues: resting.suffix(14).compactMap(\.heartRateDouble),
                explanation: "Sustained elevation of resting heart rate and temperature relative to your personal 30-day baseline is an early indicator of illness."
            ),
            deepLinkPath: "/warnings/getting-sick"
        )
    }

    // MARK: - Fatigue / Recovery

    /// Fires when:
    ///  - 7-day average resting HR is elevated by ≥ fatigueHRThreshold (%) above baseline, AND
    ///  - 7-day average RMSSD (HRV) is depressed to ≤ fatigueHRVThreshold (%) of baseline.
    ///
    /// Returns nil if fewer than `minimumBaselineDays` of data are available.
    static func checkFatigue(readings: [Reading], profile: UserProfile) -> HealthWarning? {
        let sorted = readings.sorted { $0.timestamp < $1.timestamp }
        guard hasEnoughHistory(sorted, days: minimumBaselineDays) else { return nil }

        let resting = restingReadings(sorted)
        guard !resting.isEmpty else { return nil }

        let hrBaseline  = rollingAverage(readings: resting, days: 30, keyPath: \.heartRateDouble)
        let hrvBaseline = rollingAverage(readings: resting, days: 30, keyPath: \.rmssd)
        guard let hrBaseline, let hrvBaseline, hrvBaseline > 0 else { return nil }

        let recentHR  = rollingAverage(readings: resting, days: 7, keyPath: \.heartRateDouble)
        let recentHRV = rollingAverage(readings: resting, days: 7, keyPath: \.rmssd)
        guard let recentHR, let recentHRV else { return nil }

        let hrElevatedFraction  = (recentHR  - hrBaseline)  / hrBaseline
        let hrvDepressedFraction = recentHRV / hrvBaseline

        let hrFatigued  = hrElevatedFraction  >= profile.fatigueHRThreshold
        let hrvFatigued = hrvDepressedFraction <= profile.fatigueHRVThreshold

        guard hrFatigued && hrvFatigued else { return nil }

        return HealthWarning(
            id: UUID(),
            type: .fatigueRecovery,
            firedAt: Date(),
            resolvedAt: nil,
            title: "Poor Recovery Detected",
            message: String(
                format: "Your resting HR is %.0f%% above baseline and HRV is %.0f%% of baseline — signs of incomplete recovery.",
                hrElevatedFraction * 100,
                hrvDepressedFraction * 100
            ),
            context: HealthWarning.WarningContext(
                triggerValues: [
                    "recentHR":  recentHR,
                    "recentHRV": recentHRV,
                    "hrElevatedPct":  hrElevatedFraction  * 100,
                    "hrvDepressedPct": hrvDepressedFraction * 100
                ],
                baselineValues: [
                    "hrBaseline":  hrBaseline,
                    "hrvBaseline": hrvBaseline
                ],
                trendValues: resting.suffix(14).compactMap(\.rmssd),
                explanation: "Elevated resting HR combined with depressed HRV (RMSSD) indicates incomplete physiological recovery."
            ),
            deepLinkPath: "/warnings/fatigue"
        )
    }

    // MARK: - Helpers

    /// Compute the rolling average of a numeric key path over the last N days.
    static func rollingAverage(
        readings: [Reading],
        days: Int,
        keyPath: KeyPath<Reading, Double?>
    ) -> Double? {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let values = readings
            .filter { $0.timestamp >= cutoff }
            .compactMap { $0[keyPath: keyPath] }
        return values.isEmpty ? nil : values.average
    }

    /// Filter readings to resting state only (activity == .rest or .sleep).
    static func restingReadings(_ readings: [Reading]) -> [Reading] {
        readings.filter { $0.activity == .rest || $0.activity == .sleep }
    }

    /// Compute RMSSD (in milliseconds) from an array of RR intervals given in
    /// seconds. Returns nil if < 2 values.
    static func rmssd(from rrIntervals: [Double]) -> Double? {
        guard rrIntervals.count >= 2 else { return nil }
        var sumSq = 0.0
        for i in 1 ..< rrIntervals.count {
            let diff = rrIntervals[i] - rrIntervals[i - 1]
            sumSq += diff * diff
        }
        return sqrt(sumSq / Double(rrIntervals.count - 1)) * 1000.0
    }

    // MARK: - Private Helpers

    private static func hasEnoughHistory(_ readings: [Reading], days: Int) -> Bool {
        guard let earliest = readings.first?.timestamp else { return false }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return earliest <= cutoff
    }

    private static func startOfToday() -> Date {
        Calendar.current.startOfDay(for: Date())
    }
}

// MARK: - Reading Convenience Extensions

private extension Reading {
    var heartRateDouble: Double? {
        heartRate.map { Double($0) }
    }
}

// MARK: - Array Average Helper

private extension Array where Element == Double {
    var average: Double {
        isEmpty ? 0 : reduce(0, +) / Double(count)
    }
}
