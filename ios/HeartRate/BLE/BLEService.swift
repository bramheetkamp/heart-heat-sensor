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
    private var cancellables = Set<AnyCancellable>()
    private let hapticGenerator = UINotificationFeedbackGenerator()

    // MARK: - Init

    init(transport: BLETransportProtocol) {
        self.transport = transport
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
                self?.latestTemp[measurement.site] = measurement
            }
            .store(in: &cancellables)
    }
}
