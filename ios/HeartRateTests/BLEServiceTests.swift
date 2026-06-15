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
