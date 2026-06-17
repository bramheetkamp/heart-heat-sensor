import XCTest
import Foundation
@testable import HeartRate

@MainActor
final class BLEServiceTests: XCTestCase {

    /// A connected device's live HR + temperature measurements should be
    /// persisted as Readings so History/Dashboard/Alerts can display them.
    func test_liveMeasurements_persistAsReadings() async throws {
        let store = DataStore(inMemory: true)
        let mock = MockBLETransport()
        let service = BLEService(transport: mock, dataStore: store)
        mock.apply(config: StreamConfig())

        // startScanning() flips the mock to .connected after a short delay.
        mock.startScanning()
        try await Task.sleep(nanoseconds: 700_000_000)
        XCTAssertTrue(service.isConnected, "Mock should report connected after scanning")

        // Feed one HR + both temperature sites; core temp triggers persistence.
        mock.injectHR(72, rrIntervals: [0.83, 0.84])
        mock.injectTemperature(35.8, site: .skin)
        mock.injectTemperature(37.0, site: .core)
        try await Task.sleep(nanoseconds: 300_000_000)

        let readings = try store.recentReadings(days: 1)
        XCTAssertFalse(readings.isEmpty, "A live sample should have been persisted")
        let last = try XCTUnwrap(readings.last)
        XCTAssertEqual(last.heartRate, 72)
        XCTAssertEqual(last.tempCore ?? 0, 37.0, accuracy: 0.001)
        XCTAssertEqual(last.tempSkin ?? 0, 35.8, accuracy: 0.001)
    }

    /// A BodyTempSensor (Profile B) streams temperature + EDA but NO heart rate.
    /// Such a device must still persist Readings (regression for the previous
    /// bug where persistence required a heart-rate value).
    func test_temperatureAndEDAOnly_persistsWithoutHeartRate() async throws {
        let store = DataStore(inMemory: true)
        let mock = MockBLETransport()
        let service = BLEService(transport: mock, dataStore: store)

        mock.startScanning()
        try await Task.sleep(nanoseconds: 700_000_000)
        XCTAssertTrue(service.isConnected)

        // No HR injected — only skin/core temperature and EDA, like Profile B.
        mock.injectEDA(8.4)
        mock.injectTemperature(35.9, site: .skin)
        mock.injectTemperature(37.2, site: .core) // core arrival triggers persist
        try await Task.sleep(nanoseconds: 300_000_000)

        let readings = try store.recentReadings(days: 1)
        let last = try XCTUnwrap(readings.last)
        XCTAssertNil(last.heartRate, "No HR sensor on this device")
        XCTAssertEqual(last.tempCore ?? 0, 37.2, accuracy: 0.001)
        XCTAssertEqual(last.eda ?? 0, 8.4, accuracy: 0.001)
        XCTAssertEqual(last.activity, .unknown, "Activity can't be inferred without HR")
    }

    /// EDA from a connected device is exposed on the service and persisted.
    func test_edaMeasurement_isPublishedAndStored() async throws {
        let store = DataStore(inMemory: true)
        let mock = MockBLETransport()
        let service = BLEService(transport: mock, dataStore: store)

        mock.startScanning()
        try await Task.sleep(nanoseconds: 700_000_000)

        mock.injectEDA(11.2)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(service.latestEDA?.conductance ?? 0, 11.2, accuracy: 0.001)
    }

    /// Live samples drive the always-on heat-strain monitor: streaming a hot
    /// core temperature updates `heatAssessment` to critical without any in-app
    /// workout being started. (Regression for "switching scenario / live data
    /// doesn't update anything".)
    func test_liveStream_updatesHeatAssessment() async throws {
        let store = DataStore(inMemory: true)
        let mock = MockBLETransport()
        let service = BLEService(transport: mock, dataStore: store)

        mock.startScanning()
        try await Task.sleep(nanoseconds: 700_000_000)
        XCTAssertEqual(service.heatAssessment.level, .nominal, "Starts nominal before any hot data")

        // Simulate an overheating workout: active HR + a dangerously high core temp.
        mock.injectHR(150, rrIntervals: [0.40, 0.41])
        mock.injectTemperature(36.5, site: .skin)
        mock.injectTemperature(40.5, site: .core)   // core arrival drives assessment
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(service.latestHR?.heartRate, 150, "Live HR is published")
        XCTAssertEqual(service.heatAssessment.level, .critical, "Hot core temp escalates to critical")
        XCTAssertFalse(service.heatTrend.isEmpty, "Trend buffer captured the sample")
    }

    /// Switching scenarios must clear the previous session's *live* readings so a
    /// prior overheating run doesn't keep firing warnings. Live mock readings are
    /// tagged "DEMO" (and legacy "Mock Device"/"LIVE" are also purged) by
    /// seedReadings. (Regression for "switching to Normal Week still shows
    /// overheating / the angry bear".)
    func test_switchingScenario_clearsStaleHotLiveReadings() async throws {
        let store = DataStore(inMemory: true)
        let demo = DemoModeService()

        // Simulate hot live readings left over from an Overheating session.
        let hotDemo = Reading(); hotDemo.timestamp = Date(); hotDemo.tempCore = 40.2
        hotDemo.heartRate = 150; hotDemo.activity = .active; hotDemo.deviceId = "DEMO"
        let hotLegacy = Reading(); hotLegacy.timestamp = Date(); hotLegacy.tempCore = 39.8
        hotLegacy.heartRate = 148; hotLegacy.activity = .active; hotLegacy.deviceId = "Mock Device"
        try store.save(readings: [hotDemo, hotLegacy])

        // Switch to Normal Week → reseed should purge the hot readings.
        try await demo.seedReadings(scenario: .normalWeek, into: store)

        let readings = try store.recentReadings(days: 2)
        let hottest = readings.compactMap(\.tempCore).max() ?? 0
        XCTAssertLessThan(hottest, 38.5, "No leftover hot readings after switching to Normal Week")

        let warnings = WarningsEngine.compute(readings: readings, profile: UserProfile())
        XCTAssertFalse(warnings.contains { $0.type == .overheating },
                       "Overheating warning must clear after switching to Normal Week")
    }

    /// With no connection, injected measurements must not be persisted.
    func test_measurementsWithoutConnection_areNotPersisted() async throws {
        let store = DataStore(inMemory: true)
        let mock = MockBLETransport()
        _ = BLEService(transport: mock, dataStore: store)

        // No startScanning() → not connected.
        mock.injectHR(80, rrIntervals: [0.75])
        mock.injectTemperature(37.1, site: .core)
        try await Task.sleep(nanoseconds: 200_000_000)

        let readings = try store.recentReadings(days: 1)
        XCTAssertTrue(readings.isEmpty, "Nothing should persist while disconnected")
    }
}
