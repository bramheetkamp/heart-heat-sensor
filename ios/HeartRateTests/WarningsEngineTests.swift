import XCTest
import Foundation
@testable import HeartRate

final class WarningsEngineTests: XCTestCase {

    // MARK: - Helpers

    private func makeReading(
        timestamp: Date,
        hr: Int? = 65,
        rr: [Double] = [0.92, 0.90, 0.93],
        tempCore: Double? = 36.6,
        tempSkin: Double? = 36.0,
        eda: Double? = nil,
        activity: Reading.ActivityLevel = .rest
    ) -> Reading {
        let r = Reading()
        r.id = UUID()
        r.timestamp = timestamp
        r.heartRate = hr
        r.rrIntervals = rr
        r.tempCore = tempCore
        r.tempSkin = tempSkin
        r.eda = eda
        r.activity = activity
        r.deviceId = "test"
        r.synced = false
        return r
    }

    private func makeReadings(days: Int, hrBase: Double, tempBase: Double,
                               hrDelta: Double = 0, tempDelta: Double = 0,
                               eda: Double? = nil,
                               startDaysAgo: Int = 0) -> [Reading] {
        var readings: [Reading] = []
        let now = Date()
        for day in 0..<days {
            for hour in [1, 7, 13, 19] {  // 4 readings per day
                let t = Calendar.current.date(byAdding: .hour, value: -((startDaysAgo + day) * 24 + (24 - hour)), to: now)!
                let dayFactor = Double(days - day - 1)
                let reading = makeReading(
                    timestamp: t,
                    hr: Int(hrBase + hrDelta * dayFactor / Double(days)),
                    tempCore: tempBase + tempDelta * dayFactor / Double(days),
                    eda: eda
                )
                readings.append(reading)
            }
        }
        return readings.sorted { $0.timestamp < $1.timestamp }
    }

    private func defaultProfile() -> UserProfile {
        let p = UserProfile()
        p.id = UUID()
        p.displayName = "Test"
        p.overheatingThreshold = 38.5
        p.sickHRThreshold = 5.0
        p.sickTempThreshold = 0.3
        p.fatigueHRThreshold = 0.08
        p.fatigueHRVThreshold = 0.80
        p.createdAt = Date()
        return p
    }

    // MARK: - Overheating

    func test_overheating_aboveThreshold() {
        let profile = defaultProfile()
        var readings = makeReadings(days: 30, hrBase: 60, tempBase: 36.6)
        // Add a hot reading in the last 24h
        let hotReading = makeReading(
            timestamp: Date().addingTimeInterval(-3600),
            tempCore: 39.1,
            activity: .active
        )
        readings.append(hotReading)

        let warnings = WarningsEngine.compute(readings: readings, profile: profile)
        XCTAssertTrue(warnings.contains { $0.type == .overheating },
                      "Should fire overheating when tempCore > 38.5°C in last 24h")
    }

    func test_noOverheating_normalTemp() {
        let profile = defaultProfile()
        let readings = makeReadings(days: 30, hrBase: 60, tempBase: 36.6)
        let warnings = WarningsEngine.compute(readings: readings, profile: profile)
        XCTAssertFalse(warnings.contains { $0.type == .overheating })
    }

    func test_overheating_rapidRise() {
        let profile = defaultProfile()
        var readings = makeReadings(days: 30, hrBase: 60, tempBase: 36.6)
        let now = Date()
        // Two readings 20 minutes apart with >1°C rise
        readings.append(makeReading(timestamp: now.addingTimeInterval(-1200), tempCore: 36.8, activity: .active))
        readings.append(makeReading(timestamp: now.addingTimeInterval(-600),  tempCore: 38.0, activity: .active))

        let warnings = WarningsEngine.compute(readings: readings, profile: profile)
        XCTAssertTrue(warnings.contains { $0.type == .overheating },
                      "Should fire overheating on rapid rise >1°C in 30 min")
    }

    // MARK: - Getting Sick

    func test_gettingSick_elevatedHR() {
        let profile = defaultProfile()
        // 30-day baseline: 60 bpm. Recent 7 days: 67 bpm (≥5 above baseline → fires).
        // Baseline window sits *before* the recent 7 days so the two don't overlap.
        var readings = makeReadings(days: 23, hrBase: 60, tempBase: 36.5, startDaysAgo: 7)
        let recent = makeReadings(days: 7, hrBase: 67, tempBase: 36.5)
        readings.append(contentsOf: recent)

        let warnings = WarningsEngine.compute(readings: readings, profile: profile)
        XCTAssertTrue(warnings.contains { $0.type == .gettingSick },
                      "Should fire gettingSick when resting HR consistently ≥5 above 30-day baseline")
    }

    func test_noGettingSick_insufficientData() {
        let profile = defaultProfile()
        // Only 7 days of data — not enough for 30-day baseline
        let readings = makeReadings(days: 7, hrBase: 70, tempBase: 36.8)
        let warnings = WarningsEngine.compute(readings: readings, profile: profile)
        XCTAssertFalse(warnings.contains { $0.type == .gettingSick },
                       "Should not fire with fewer than 14 days of data")
    }

    // MARK: - Fatigue / Recovery

    func test_fatigue_elevatedHR_lowHRV() {
        let profile = defaultProfile()
        // Baseline: 60 bpm, default RR (RMSSD ≈ 25ms), placed before the recent window.
        // Recent: 67 bpm (+~9%), very regular RR → near-zero HRV.
        var readings = makeReadings(days: 23, hrBase: 60, tempBase: 36.5, startDaysAgo: 7)
        // Add 7 days of high HR + very low HRV (regular RR → near-zero RMSSD)
        let now = Date()
        for day in 0..<7 {
            for hour in [1, 7, 13, 19] {
                let t = Calendar.current.date(byAdding: .hour, value: -(day * 24 + (24 - hour)), to: now)!
                let r = makeReading(
                    timestamp: t,
                    hr: 67,
                    rr: [0.895, 0.895, 0.895, 0.895],  // perfectly regular → RMSSD = 0
                    tempCore: 36.6
                )
                readings.append(r)
            }
        }

        let warnings = WarningsEngine.compute(readings: readings, profile: profile)
        XCTAssertTrue(warnings.contains { $0.type == .fatigueRecovery },
                      "Should fire fatigueRecovery when elevated HR + depressed HRV vs baseline")
    }

    func test_noFatigue_normalRecovery() {
        let profile = defaultProfile()
        let readings = makeReadings(days: 30, hrBase: 60, tempBase: 36.5)
        let warnings = WarningsEngine.compute(readings: readings, profile: profile)
        XCTAssertFalse(warnings.contains { $0.type == .fatigueRecovery })
    }

    // MARK: - Warning metadata

    func test_warningHasExplanation() {
        let profile = defaultProfile()
        var readings = makeReadings(days: 23, hrBase: 60, tempBase: 36.5, startDaysAgo: 7)
        readings.append(contentsOf: makeReadings(days: 7, hrBase: 67, tempBase: 36.5))
        let warnings = WarningsEngine.compute(readings: readings, profile: profile)
        let sick = warnings.first(where: { $0.type == .gettingSick })
        XCTAssertNotNil(sick, "gettingSick warning should fire for the elevated-HR scenario")
        if let w = sick {
            XCTAssertFalse(w.context.explanation.isEmpty, "Warning should include explanation text")
            XCTAssertFalse(w.context.triggerValues.isEmpty, "Warning should include trigger values")
            XCTAssertFalse(w.context.baselineValues.isEmpty, "Warning should include baseline values")
        }
    }

    // MARK: - EDA as corroborating context

    func test_gettingSick_includesEDAContextWhenPresent() {
        let profile = defaultProfile()
        // Baseline EDA ~5 µS; recent week elevated to ~9 µS (>1.2× baseline).
        var readings = makeReadings(days: 23, hrBase: 60, tempBase: 36.5, eda: 5.0, startDaysAgo: 7)
        readings.append(contentsOf: makeReadings(days: 7, hrBase: 67, tempBase: 36.5, eda: 9.0))

        let sick = WarningsEngine.compute(readings: readings, profile: profile)
            .first { $0.type == .gettingSick }
        let w = try! XCTUnwrap(sick)
        XCTAssertNotNil(w.context.triggerValues["avgEDA"], "EDA should be surfaced when present")
        XCTAssertNotNil(w.context.baselineValues["edaBaseline"])
        XCTAssertTrue(w.context.explanation.contains("conductance"),
                      "Elevated EDA should be mentioned in the explanation")
    }

    func test_gettingSick_omitsEDAContextForHROnlyDevice() {
        let profile = defaultProfile()
        // No EDA at all (standard HR strap).
        var readings = makeReadings(days: 23, hrBase: 60, tempBase: 36.5, startDaysAgo: 7)
        readings.append(contentsOf: makeReadings(days: 7, hrBase: 67, tempBase: 36.5))

        let sick = WarningsEngine.compute(readings: readings, profile: profile)
            .first { $0.type == .gettingSick }
        let w = try! XCTUnwrap(sick)
        XCTAssertNil(w.context.triggerValues["avgEDA"], "No EDA key when device never reports it")
    }

    // MARK: - RMSSD

    func test_rmssd_calculation() {
        // RR intervals: [0.800, 0.820, 0.800, 0.820]
        // Diffs: [0.020, -0.020, 0.020]
        // Squared: [0.0004, 0.0004, 0.0004]
        // Mean: 0.0004; sqrt = 0.020 s = 20 ms
        let r = makeReading(timestamp: Date(), rr: [0.800, 0.820, 0.800, 0.820])
        XCTAssertNotNil(r.rmssd)
        XCTAssertEqual(r.rmssd!, 0.020 * 1000, accuracy: 0.1) // should be ≈ 20ms
    }

    func test_rmssd_nilForEmptyRR() {
        let r = makeReading(timestamp: Date(), rr: [])
        XCTAssertNil(r.rmssd)
    }

    func test_rmssd_nilForSingleRR() {
        let r = makeReading(timestamp: Date(), rr: [0.9])
        XCTAssertNil(r.rmssd)
    }
}
