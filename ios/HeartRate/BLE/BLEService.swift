import Foundation
import Combine
import UIKit

// MARK: - BLEService

@MainActor
final class BLEService: ObservableObject {

    // MARK: - Published State

    @Published var connectionState: BLEConnectionState = .disconnected
    @Published var latestHR: HRMeasurement?
    @Published var latestTemp: [TemperatureSite: TemperatureMeasurement] = [:]
    @Published var isConnected: Bool = false

    // MARK: - Private

    private let transport: BLETransportProtocol
    private let dataStore: DataStore?
    private var cancellables = Set<AnyCancellable>()
    private let hapticGenerator = UINotificationFeedbackGenerator()

    // MARK: - Init

    /// - Parameter dataStore: when provided, live measurements from a connected
    ///   device are persisted as `Reading`s so History/Dashboard/Alerts populate.
    init(transport: BLETransportProtocol, dataStore: DataStore? = nil) {
        self.transport = transport
        self.dataStore = dataStore
        bindTransport()
        hapticGenerator.prepare()
    }

    // MARK: - Public Interface

    func startScanning() {
        transport.startScanning()
    }

    func stopScanning() {
        transport.stopScanning()
    }

    func disconnect() {
        transport.disconnect()
    }

    // MARK: - Private Binding

    private func bindTransport() {
        transport.connectionStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                let wasConnected = self.isConnected
                self.connectionState = state
                self.isConnected = state.isConnected

                // Haptic feedback on connection events
                if !wasConnected && state.isConnected {
                    self.hapticGenerator.notificationOccurred(.success)
                } else if wasConnected && !state.isConnected {
                    self.hapticGenerator.notificationOccurred(.warning)
                } else if case .error = state {
                    self.hapticGenerator.notificationOccurred(.error)
                }
            }
            .store(in: &cancellables)

        transport.hrMeasurementPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] measurement in
                self?.latestHR = measurement
            }
            .store(in: &cancellables)

        transport.temperaturePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] measurement in
                guard let self else { return }
                self.latestTemp[measurement.site] = measurement
                // Core temperature drives the persistence cadence (~every 5s),
                // combining the latest HR + both temperature sites into a Reading.
                if measurement.site == .core {
                    self.persistLiveSample()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Live Persistence

    /// Persist a combined snapshot of the latest live measurements as a Reading,
    /// so a connected device (real or, on the simulator, the mock) populates the
    /// data store that the dashboard and history read from.
    private func persistLiveSample() {
        guard let dataStore, isConnected, let hr = latestHR else { return }

        let deviceName: String
        if case .connected(let name) = connectionState { deviceName = name } else { deviceName = "LIVE" }

        let reading = Reading(
            timestamp: Date(),
            heartRate: hr.heartRate,
            rrIntervals: hr.rrIntervals,
            tempCore: latestTemp[.core]?.value,
            tempSkin: latestTemp[.skin]?.value,
            activity: hr.heartRate >= 100 ? .active : .rest,
            deviceId: deviceName
        )
        try? dataStore.save(reading: reading)
    }
}
