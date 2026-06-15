import Foundation

// MARK: - DemoScenario

enum DemoScenario: String, CaseIterable, Identifiable {
    case normalWeek      = "Normal Week"
    case overheatWorkout = "Overheating Workout"
    case gettingSick     = "Getting Sick (3 days)"
    case poorRecovery    = "Poor Recovery"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .normalWeek:
            return "35 days of typical resting HR (62–72 bpm) and stable core temperature (36.6–37.0 °C). No warnings triggered."
        case .overheatWorkout:
            return "Includes a simulated intense workout session where core temperature spikes above 38.5 °C, triggering an overheating alert."
        case .gettingSick:
            return "Resting HR and temperature gradually rise over 3 days above personal baseline, simulating early-illness detection."
        case .poorRecovery:
            return "Chronically elevated resting HR and suppressed HRV (RMSSD) over 14 days, triggering a fatigue/poor-recovery alert."
        }
    }
}

// MARK: - StreamConfig

struct StreamConfig {
    var hrRange: ClosedRange<Double>
    var coreTemp: Double
    var skinTemp: Double
    /// Baseline skin conductance in µS. Sympathetic arousal (stress, fever onset,
    /// poor recovery) raises EDA, so scenarios that fire warnings use higher values.
    var eda: Double
    var includeSpike: Bool

    init(
        hrRange: ClosedRange<Double> = 62...72,
        coreTemp: Double = 36.8,
        skinTemp: Double = 35.7,
        eda: Double = 5.0,
        includeSpike: Bool = false
    ) {
        self.hrRange = hrRange
        self.coreTemp = coreTemp
        self.skinTemp = skinTemp
        self.eda = eda
        self.includeSpike = includeSpike
    }
}

// MARK: - DemoModeService

@MainActor
final class DemoModeService: ObservableObject {

    @Published var activeScenario: DemoScenario = .normalWeek

    // MARK: - Stream Config

    /// Returns the live-stream HR/temperature configuration for a given scenario.
    func currentStreamConfig(for scenario: DemoScenario) -> StreamConfig {
        switch scenario {
        case .normalWeek:
            return StreamConfig(hrRange: 62...72, coreTemp: 36.8, skinTemp: 35.7, eda: 5.0, includeSpike: false)
        case .overheatWorkout:
            return StreamConfig(hrRange: 100...155, coreTemp: 38.9, skinTemp: 37.5, eda: 14.0, includeSpike: true)
        case .gettingSick:
            return StreamConfig(hrRange: 68...80, coreTemp: 37.4, skinTemp: 36.2, eda: 8.0, includeSpike: false)
        case .poorRecovery:
            return StreamConfig(hrRange: 72...84, coreTemp: 37.1, skinTemp: 36.0, eda: 9.5, includeSpike: false)
        }
    }

    // MARK: - Seed Historical Data

    /// Generate ~35 days of Reading objects matching the scenario and persist them.
    func seedReadings(scenario: DemoScenario, into store: DataStore) async throws {
        let calendar = Calendar.current
        let now = Date()
        let daysBack = 35

        // Clear any previously-seeded demo data so switching scenarios is clean.
        try? store.deleteReadings(deviceId: "DEMO")

        var readings: [Reading] = []

        for dayOffset in 0 ..< daysBack {
            guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: now) else { continue }

            // Multiple readings per day: 4 resting + 2 active
            let readingTimes = dailyReadingSchedule(for: day)

            for (time, activity) in readingTimes {
                let reading = buildReading(
                    scenario: scenario,
                    timestamp: time,
                    activity: activity,
                    dayOffset: dayOffset,
                    calendar: calendar
                )
                readings.append(reading)
            }
        }

        // Insert in chronological order
        for reading in readings.sorted(by: { $0.timestamp < $1.timestamp }) {
            try store.save(reading: reading)
        }
    }

    // MARK: - Private Helpers

    private func dailyReadingSchedule(for day: Date) -> [(Date, Reading.ActivityLevel)] {
        let calendar = Calendar.current
        var schedule: [(Date, Reading.ActivityLevel)] = []

        // Resting readings: 02:00, 06:00, 12:00, 22:00
        for hour in [2, 6, 12, 22] {
            if let t = calendar.date(bySettingHour: hour, minute: Int.random(in: 0...59), second: 0, of: day) {
                schedule.append((t, hour < 5 ? .sleep : .rest))
            }
        }
        // Active readings: 08:00, 18:00
        for hour in [8, 18] {
            if let t = calendar.date(bySettingHour: hour, minute: Int.random(in: 0...59), second: 0, of: day) {
                schedule.append((t, .active))
            }
        }
        return schedule
    }

    private func buildReading(
        scenario: DemoScenario,
        timestamp: Date,
        activity: Reading.ActivityLevel,
        dayOffset: Int,
        calendar: Calendar
    ) -> Reading {
        switch scenario {
        case .normalWeek:
            return normalReading(timestamp: timestamp, activity: activity)

        case .overheatWorkout:
            // Spike on day 3 (dayOffset == 32 from 35 days back → day 3 from now = dayOffset 32)
            // Use dayOffset 2 for clarity: the workout was 2 days ago
            let isWorkoutDay = dayOffset == 2
            let isWorkoutTime: Bool = {
                let hour = calendar.component(.hour, from: timestamp)
                return isWorkoutDay && (hour == 8 || hour == 18) && activity == .active
            }()
            if isWorkoutTime {
                return overheatReading(timestamp: timestamp)
            }
            return normalReading(timestamp: timestamp, activity: activity)

        case .gettingSick:
            // Last 3 days show elevated HR + temp
            let elevatedPhase = dayOffset < 3
            return sickReading(timestamp: timestamp, activity: activity, elevated: elevatedPhase)

        case .poorRecovery:
            // Consistently elevated HR, suppressed HRV across all days
            return fatigueReading(timestamp: timestamp, activity: activity)
        }
    }

    // MARK: - Scenario-Specific Reading Builders

    private func normalReading(timestamp: Date, activity: Reading.ActivityLevel) -> Reading {
        let hrBase: Double = activity == .active ? Double.random(in: 95...130) : Double.random(in: 62...72)
        let rr = rrIntervals(fromBPM: hrBase)
        return Reading(
            timestamp: timestamp,
            heartRate: Int(hrBase),
            rrIntervals: rr,
            tempCore: Double.random(in: 36.6...37.0),
            tempSkin: Double.random(in: 35.5...35.9),
            eda: Double.random(in: 4.0...6.5),
            activity: activity,
            deviceId: "DEMO"
        )
    }

    private func overheatReading(timestamp: Date) -> Reading {
        let hr = Double.random(in: 140...165)
        let rr = rrIntervals(fromBPM: hr)
        return Reading(
            timestamp: timestamp,
            heartRate: Int(hr),
            rrIntervals: rr,
            tempCore: Double.random(in: 38.6...39.2),
            tempSkin: Double.random(in: 37.4...37.9),
            eda: Double.random(in: 12.0...16.0),
            activity: .active,
            deviceId: "DEMO"
        )
    }

    private func sickReading(timestamp: Date, activity: Reading.ActivityLevel, elevated: Bool) -> Reading {
        let hrBase: Double = elevated
            ? Double.random(in: 75...85)
            : Double.random(in: 62...72)
        let tempBase: Double = elevated
            ? Double.random(in: 37.3...37.8)
            : Double.random(in: 36.6...37.0)
        let rr = rrIntervals(fromBPM: hrBase)
        return Reading(
            timestamp: timestamp,
            heartRate: Int(hrBase),
            rrIntervals: rr,
            tempCore: tempBase,
            tempSkin: tempBase - Double.random(in: 0.9...1.1),
            eda: elevated ? Double.random(in: 7.0...9.5) : Double.random(in: 4.0...6.5),
            activity: activity,
            deviceId: "DEMO"
        )
    }

    private func fatigueReading(timestamp: Date, activity: Reading.ActivityLevel) -> Reading {
        // Elevated resting HR + suppressed HRV (tighter RR intervals)
        let hrBase: Double = activity == .active
            ? Double.random(in: 120...145)
            : Double.random(in: 75...88)

        // Suppressed HRV: very uniform RR intervals (low variation)
        let baseRR = 60.0 / hrBase
        let rr: [Double] = (0..<4).map { _ in baseRR * Double.random(in: 0.995...1.005) }

        return Reading(
            timestamp: timestamp,
            heartRate: Int(hrBase),
            rrIntervals: rr,
            tempCore: Double.random(in: 36.8...37.2),
            tempSkin: Double.random(in: 35.7...36.0),
            eda: Double.random(in: 8.5...11.0),
            activity: activity,
            deviceId: "DEMO"
        )
    }

    /// Derive realistic RR intervals from a BPM value with ±2% natural variation.
    private func rrIntervals(fromBPM bpm: Double, count: Int = 4) -> [Double] {
        let base = 60.0 / bpm
        return (0..<count).map { _ in base * Double.random(in: 0.97...1.03) }
    }
}
