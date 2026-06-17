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
        // Includes legacy live-stream tags ("Mock Device"/"LIVE") written before
        // demo readings were unified under "DEMO", so stale hot readings from a
        // prior overheating session don't keep firing warnings after a switch.
        try? store.deleteReadings(deviceId: "DEMO")
        try? store.deleteReadings(deviceId: "Mock Device")
        try? store.deleteReadings(deviceId: "LIVE")

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

        // Insert in chronological order, in a single transaction so the
        // dashboard's @Query refreshes once rather than once per row.
        try store.save(readings: readings.sorted(by: { $0.timestamp < $1.timestamp }))
    }

    // MARK: - Private Helpers

    private func dailyReadingSchedule(for day: Date) -> [(Date, Reading.ActivityLevel)] {
        let calendar = Calendar.current
        let now = Date()
        var schedule: [(Date, Reading.ActivityLevel)] = []

        // Sleep block: 8 readings ~90 min apart from 22:00 to 06:30.
        // Filtering future timestamps ensures demo data never contains readings
        // that haven't "happened" yet relative to when the app is opened.
        for (hour, minute) in [(22,0),(23,30),(1,0),(2,30),(4,0),(5,0),(6,0),(6,30)] {
            if let t = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day),
               t <= now {
                schedule.append((t, .sleep))
            }
        }
        // Daytime: morning active, midday rest, evening active
        for (hour, minute, activity): (Int, Int, Reading.ActivityLevel) in [
            (8,  Int.random(in: 0...59), .active),
            (12, Int.random(in: 0...59), .rest),
            (18, Int.random(in: 0...59), .active)
        ] {
            if let t = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day),
               t <= now {
                schedule.append((t, activity))
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
        let hrBase: Double
        switch activity {
        case .active: hrBase = Double.random(in: 95...130)
        case .sleep:  hrBase = Double.random(in: 52...62)
        default:      hrBase = Double.random(in: 62...72)
        }
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
        let hrBase: Double
        if elevated {
            switch activity {
            case .active: hrBase = Double.random(in: 100...115)
            case .sleep:  hrBase = Double.random(in: 65...73)
            default:      hrBase = Double.random(in: 75...85)
            }
        } else {
            switch activity {
            case .active: hrBase = Double.random(in: 95...130)
            case .sleep:  hrBase = Double.random(in: 52...62)
            default:      hrBase = Double.random(in: 62...72)
            }
        }
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
        // Elevated resting + sleep HR, suppressed HRV (tight RR intervals) — signs of poor recovery.
        let hrBase: Double
        switch activity {
        case .active: hrBase = Double.random(in: 120...145)
        case .sleep:  hrBase = Double.random(in: 62...72)  // elevated vs. normal 52-62
        default:      hrBase = Double.random(in: 75...88)  // chronically elevated resting HR
        }

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
