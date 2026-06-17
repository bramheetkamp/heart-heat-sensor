import XCTest
import Foundation
@testable import HeartRate

/// Tests for the graded, real-time workout heat-strain engine.
final class HeatStrainEngineTests: XCTestCase {

    private let caution = 38.5            // default overheating threshold
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func sample(_ secondsAgo: TimeInterval, _ core: Double) -> HeatStrainEngine.Sample {
        HeatStrainEngine.Sample(time: now.addingTimeInterval(-secondsAgo), core: core)
    }

    // MARK: - Thresholds

    func testThresholdHelpers() {
        XCTAssertEqual(HeatStrainEngine.seriousThreshold(caution: caution), 39.3, accuracy: 0.0001)
        XCTAssertEqual(HeatStrainEngine.criticalThreshold(caution: caution), 40.0, accuracy: 0.0001)
    }

    // MARK: - Absolute level from latest core temp

    func testNominalWhenCool() {
        let a = HeatStrainEngine.assess(samples: [sample(0, 37.4)], isActive: true, caution: caution, now: now)
        XCTAssertEqual(a.level, .nominal)
        XCTAssertFalse(a.escalatedByRise)
    }

    func testElevatedAtCaution() {
        let a = HeatStrainEngine.assess(samples: [sample(0, 38.6)], isActive: true, caution: caution, now: now)
        XCTAssertEqual(a.level, .elevated)
    }

    func testSeriousAtSeriousThreshold() {
        let a = HeatStrainEngine.assess(samples: [sample(0, 39.4)], isActive: true, caution: caution, now: now)
        XCTAssertEqual(a.level, .serious)
    }

    func testCriticalAtCriticalThreshold() {
        let a = HeatStrainEngine.assess(samples: [sample(0, 40.2)], isActive: true, caution: caution, now: now)
        XCTAssertEqual(a.level, .critical)
        XCTAssertTrue(a.message.contains("STOP"))
        XCTAssertTrue(a.level.shouldAlert)
    }

    // MARK: - Rate-of-rise escalation

    func testRapidRiseEscalatesWhileActive() {
        // +0.6 °C over 5 min = 1.2 °C/10 min (≥ 0.6 trigger). Latest core 38.4 is
        // just below caution → temp level nominal, but a fast climb while active
        // should escalate to elevated.
        let samples = [sample(300, 37.8), sample(0, 38.4)]
        let a = HeatStrainEngine.assess(samples: samples, isActive: true, caution: caution, now: now)
        XCTAssertEqual(a.level, .elevated)
        XCTAssertTrue(a.escalatedByRise)
        XCTAssertNotNil(a.riseRatePer10Min)
        XCTAssertGreaterThanOrEqual(a.riseRatePer10Min!, HeatStrainEngine.rapidRisePer10Min)
    }

    func testRapidRiseIgnoredWhenInactive() {
        let samples = [sample(300, 37.8), sample(0, 38.4)]
        let a = HeatStrainEngine.assess(samples: samples, isActive: false, caution: caution, now: now)
        XCTAssertEqual(a.level, .nominal)
        XCTAssertFalse(a.escalatedByRise)
    }

    func testRapidRiseBumpsElevatedToSerious() {
        // Already elevated (38.7) + fast rise → serious.
        let samples = [sample(300, 38.1), sample(0, 38.7)]
        let a = HeatStrainEngine.assess(samples: samples, isActive: true, caution: caution, now: now)
        XCTAssertEqual(a.level, .serious)
        XCTAssertTrue(a.escalatedByRise)
    }

    func testSlowRiseDoesNotEscalate() {
        // +0.2 °C over 10 min = 0.2 °C/10 min (< 0.6). Stays at temp level.
        let samples = [sample(600, 38.4), sample(0, 38.6)]
        let a = HeatStrainEngine.assess(samples: samples, isActive: true, caution: caution, now: now)
        XCTAssertEqual(a.level, .elevated)
        XCTAssertFalse(a.escalatedByRise)
    }

    // MARK: - Rise-rate computation

    func testRiseRateComputation() {
        let samples = [sample(600, 37.0), sample(0, 38.0)] // +1.0 °C over 10 min
        let rate = HeatStrainEngine.riseRatePer10Min(sorted: samples, now: now)
        XCTAssertEqual(rate ?? 0, 1.0, accuracy: 0.001)
    }

    func testRiseRateNilForSingleSample() {
        let rate = HeatStrainEngine.riseRatePer10Min(sorted: [sample(0, 38.0)], now: now)
        XCTAssertNil(rate)
    }

    // MARK: - Empty input

    func testEmptySamplesIsNominal() {
        let a = HeatStrainEngine.assess(samples: [], isActive: true, caution: caution, now: now)
        XCTAssertEqual(a.level, .nominal)
        XCTAssertNil(a.coreTemp)
    }

    // MARK: - Reading convenience overload

    func testReadingsOverloadCriticalWhenActive() {
        let profile = UserProfile()   // caution 38.5
        let r1 = Reading(); r1.timestamp = now.addingTimeInterval(-60); r1.tempCore = 39.0; r1.activity = .active
        let r2 = Reading(); r2.timestamp = now; r2.tempCore = 40.5; r2.activity = .active
        let a = HeatStrainEngine.assess(readings: [r1, r2], profile: profile, now: now)
        XCTAssertEqual(a.level, .critical)
    }
}
