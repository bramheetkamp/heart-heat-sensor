import Foundation
import SwiftUI

// MARK: - HeatStrainEngine

/// Real-time, **graded** heat-strain assessment for workouts — the sport-focused
/// counterpart to `WarningsEngine.checkOverheating`. Where that fires a single
/// binary offline alert, this returns an escalating severity so a live training
/// session can warn early (ease off), then *harshly* tell the athlete to stop.
///
/// Pure and fully testable: no SwiftData, no side effects, no `Date.now`
/// dependency in the core (callers pass `now`). Drives the live `WorkoutView`
/// banner, haptics, and the heat-strain notification.
struct HeatStrainEngine {

    // MARK: - Level

    enum Level: Int, Comparable, CaseIterable {
        case nominal = 0   // safe range — keep going
        case elevated      // caution — ease the pace, hydrate
        case serious       // slow down NOW
        case critical      // STOP and cool down

        static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    // MARK: - Sample

    /// A single core-temperature sample. Kept deliberately tiny so the engine
    /// has no SwiftData coupling and tests can build inputs trivially.
    struct Sample: Equatable {
        let time: Date
        let core: Double   // °C
    }

    // MARK: - Assessment

    struct Assessment: Equatable {
        let level: Level
        let coreTemp: Double?         // latest core temp, if any
        let riseRatePer10Min: Double? // °C / 10 min over the recent window, if computable
        let escalatedByRise: Bool     // true when rapid rise bumped the level up
        let title: String
        let message: String
    }

    // MARK: - Tunables

    /// Threshold offsets above the user's caution threshold (`overheatingThreshold`).
    /// With the 38.5 °C default: serious = 39.3 °C, critical = 40.0 °C — tuned to
    /// exercise physiology (38–39 °C is normal under load; 40 °C is heat-illness
    /// territory and warrants an immediate stop).
    static let seriousOffset  = 0.8
    static let criticalOffset = 1.5

    /// A core rise at or beyond this rate (°C per 10 min) **while active**
    /// escalates the temperature-based level by one — a fast climb during
    /// exertion is a red flag even before the absolute threshold is crossed.
    static let rapidRisePer10Min = 0.6

    /// Window over which the rise rate is measured.
    static let riseWindow: TimeInterval = 600   // 10 minutes
    /// Below this core temp a rapid rise is not escalated (avoids false alarms at the warm-up).
    static let riseEscalationFloor = 1.0        // caution − 1.0 °C

    static func seriousThreshold(caution: Double) -> Double  { caution + seriousOffset }
    static func criticalThreshold(caution: Double) -> Double { caution + criticalOffset }

    // MARK: - Core entry point (pure)

    /// Assess heat strain from core-temp samples.
    /// - Parameters:
    ///   - samples: core-temp samples (any order); only those within `riseWindow`
    ///     of `now` inform the rise rate, but the most recent overall sets the temp.
    ///   - isActive: whether the athlete is currently exerting (gates rise escalation).
    ///   - caution: the user's caution threshold (`profile.overheatingThreshold`).
    ///   - now: current time (injected for testability).
    static func assess(samples: [Sample], isActive: Bool, caution: Double, now: Date = Date()) -> Assessment {
        let sorted = samples.sorted { $0.time < $1.time }
        guard let latest = sorted.last else {
            return Assessment(level: .nominal, coreTemp: nil, riseRatePer10Min: nil,
                              escalatedByRise: false,
                              title: title(for: .nominal), message: message(for: .nominal, escalatedByRise: false, riseRate: nil))
        }

        let core = latest.core
        let serious  = seriousThreshold(caution: caution)
        let critical = criticalThreshold(caution: caution)

        // Temperature-based level.
        var level: Level
        if core >= critical      { level = .critical }
        else if core >= serious  { level = .serious }
        else if core >= caution  { level = .elevated }
        else                     { level = .nominal }

        // Rate of rise over the trailing window (°C per 10 min).
        let riseRate = riseRatePer10Min(sorted: sorted, now: latest.time)

        // Rapid-rise escalation: while active and already warming, a steep climb
        // bumps severity one level (capped at critical).
        var escalated = false
        if isActive, let rate = riseRate, rate >= rapidRisePer10Min,
           core >= (caution - riseEscalationFloor) {
            let bumped = Level(rawValue: min(level.rawValue + 1, Level.critical.rawValue)) ?? level
            if bumped > level { level = bumped; escalated = true }
            // A fast rise should never read as fully "nominal".
            if level == .nominal { level = .elevated; escalated = true }
        }

        return Assessment(
            level: level,
            coreTemp: core,
            riseRatePer10Min: riseRate,
            escalatedByRise: escalated,
            title: title(for: level),
            message: message(for: level, escalatedByRise: escalated, riseRate: riseRate)
        )
    }

    /// Convenience overload from `Reading`s (e.g. an in-session buffer).
    static func assess(readings: [Reading], profile: UserProfile, now: Date = Date()) -> Assessment {
        let samples = readings.compactMap { r -> Sample? in
            guard let core = r.tempCore else { return nil }
            return Sample(time: r.timestamp, core: core)
        }
        let isActive = readings.sorted { $0.timestamp < $1.timestamp }.last?.activity == .active
        return assess(samples: samples, isActive: isActive, caution: profile.overheatingThreshold, now: now)
    }

    // MARK: - Rise rate

    /// °C per 10 minutes between the earliest in-window sample and the latest.
    /// Returns nil if there isn't a ≥30 s spread to measure against.
    static func riseRatePer10Min(sorted: [Sample], now: Date) -> Double? {
        let windowStart = now.addingTimeInterval(-riseWindow)
        let window = sorted.filter { $0.time >= windowStart }
        guard let first = window.first, let last = window.last else { return nil }
        let dt = last.time.timeIntervalSince(first.time)
        guard dt >= 30 else { return nil }
        let perSecond = (last.core - first.core) / dt
        return perSecond * riseWindow
    }

    // MARK: - Copy (harsh + accurate, wellness-framed)

    static func title(for level: Level) -> String {
        switch level {
        case .nominal:  return "All clear"
        case .elevated: return "Heating up"
        case .serious:  return "Getting serious"
        case .critical: return "Stop now"
        }
    }

    static func message(for level: Level, escalatedByRise: Bool, riseRate: Double?) -> String {
        let base: String
        switch level {
        case .nominal:
            base = "Core temperature is in a safe range. Keep going."
        case .elevated:
            base = "You're warming up — ease the pace and take on fluids."
        case .serious:
            base = "It's getting serious. Slow down now and back off the intensity."
        case .critical:
            base = "STOP. Your core temperature is dangerously high — stop and cool down immediately."
        }
        if escalatedByRise, let rate = riseRate, level != .nominal {
            return base + String(format: " Your core is climbing fast (+%.1f °C/10 min).", rate)
        }
        return base
    }
}

// MARK: - Presentation

extension HeatStrainEngine.Level {
    /// Banner / accent colour for this level.
    var color: Color {
        switch self {
        case .nominal:  return .green
        case .elevated: return Color(red: 0.95, green: 0.7, blue: 0.15) // amber
        case .serious:  return .orange
        case .critical: return .red
        }
    }

    var systemImage: String {
        switch self {
        case .nominal:  return "checkmark.circle.fill"
        case .elevated: return "thermometer.medium"
        case .serious:  return "thermometer.high"
        case .critical: return "exclamationmark.octagon.fill"
        }
    }

    var mascotState: MascotState {
        switch self {
        case .nominal:  return .happy
        case .elevated: return .sweating
        case .serious:  return .sweating
        case .critical: return .sweating
        }
    }

    /// Serious/critical levels warrant an active interruption (haptic + alert).
    var shouldAlert: Bool { self >= .serious }

    var shortLabel: String {
        switch self {
        case .nominal:  return "Safe"
        case .elevated: return "Caution"
        case .serious:  return "Serious"
        case .critical: return "Critical"
        }
    }
}
