import Foundation
import Combine

// MARK: - MockBLETransport

/// Simulates a BLE wearable device for demo/testing purposes.
/// Publishes realistic heart-rate and temperature data driven by a DemoScenario.
final class MockBLETransport: BLETransportProtocol {

    // MARK: - Publishers

    private let connectionStateSubject  = PassthroughSubject<BLEConnectionState, Never>()
    private let hrMeasurementSubject    = PassthroughSubject<HRMeasurement, Never>()
    private let temperatureSubject      = PassthroughSubject<TemperatureMeasurement, Never>()
    private let edaSubject              = PassthroughSubject<EDAMeasurement, Never>()

    var connectionStatePublisher: AnyPublisher<BLEConnectionState, Never> {
        connectionStateSubject.eraseToAnyPublisher()
    }
    var hrMeasurementPublisher: AnyPublisher<HRMeasurement, Never> {
        hrMeasurementSubject.eraseToAnyPublisher()
    }
    var temperaturePublisher: AnyPublisher<TemperatureMeasurement, Never> {
        temperatureSubject.eraseToAnyPublisher()
    }
    var edaPublisher: AnyPublisher<EDAMeasurement, Never> {
        edaSubject.eraseToAnyPublisher()
    }

    // MARK: - Private State

    private var streamConfig: StreamConfig = StreamConfig()
    private var hrTimer: AnyCancellable?
    private var tempTimer: AnyCancellable?
    private var isRunning = false

    // Smoothed HR state for realistic variation
    private var currentHR: Double = 72.0
    private var spikeCountdown: Int = 0

    // MARK: - Init

    init() {}

    // MARK: - Scenario Configuration

    /// Apply a demo scenario by accepting a pre-resolved StreamConfig.
    /// Callers on the @MainActor (e.g. AppEnvironment) should resolve the
    /// config from DemoModeService before passing it here.
    func apply(config: StreamConfig) {
        streamConfig = config
        currentHR = config.hrRange.lowerBound +
            (config.hrRange.upperBound - config.hrRange.lowerBound) / 2.0
        if config.includeSpike {
            spikeCountdown = Int.random(in: 15...30)
        }
    }

    /// Convenience wrapper — resolves the StreamConfig from a scenario inline.
    /// Only safe to call from the main actor (DemoModeService is @MainActor).
    @MainActor
    func applyScenario(_ scenario: DemoScenario) {
        let service = DemoModeService()
        apply(config: service.currentStreamConfig(for: scenario))
    }

    /// Inject a specific HR value on the next tick (used in unit tests).
    func injectHR(_ bpm: Int, rrIntervals: [Double] = []) {
        let measurement = HRMeasurement(heartRate: bpm, rrIntervals: rrIntervals, contactStatus: true)
        hrMeasurementSubject.send(measurement)
    }

    /// Inject a specific temperature value (used in unit tests).
    func injectTemperature(_ value: Double, site: TemperatureSite) {
        let measurement = TemperatureMeasurement(
            value: value,
            siteLabel: site.rawValue,
            site: site
        )
        temperatureSubject.send(measurement)
    }

    /// Inject a specific EDA / skin-conductance value (used in unit tests).
    func injectEDA(_ microsiemens: Double) {
        edaSubject.send(EDAMeasurement(conductance: microsiemens))
    }

    // MARK: - BLETransportProtocol

    func startScanning() {
        guard !isRunning else { return }
        isRunning = true
        connectionStateSubject.send(.scanning)

        // Simulate connection after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.isRunning else { return }
            // Tag the connection as "DEMO" so live mock readings are persisted
            // with deviceId "DEMO" and get cleared by seedReadings on every
            // scenario switch (otherwise stale hot readings keep firing warnings).
            self.connectionStateSubject.send(.connected(peripheralName: "DEMO"))
            self.startTimers()
        }
    }

    func stopScanning() {
        isRunning = false
        stopTimers()
        connectionStateSubject.send(.disconnected)
    }

    func disconnect() {
        isRunning = false
        stopTimers()
        connectionStateSubject.send(.disconnected)
    }

    // MARK: - Private Timer Management

    private func startTimers() {
        // HR every 1 second
        hrTimer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.emitHR()
            }

        // Temperature every 5 seconds
        tempTimer = Timer.publish(every: 5.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.emitTemperature()
            }

        // Emit first temperature immediately
        emitTemperature()
    }

    private func stopTimers() {
        hrTimer?.cancel()
        hrTimer = nil
        tempTimer?.cancel()
        tempTimer = nil
    }

    // MARK: - Data Simulation

    private func emitHR() {
        let low  = streamConfig.hrRange.lowerBound
        let high = streamConfig.hrRange.upperBound

        // Handle overheating spike scenario
        if streamConfig.includeSpike {
            if spikeCountdown <= 0 {
                // Ramp toward spike peak (165 bpm) for 10 ticks, then reset
                currentHR = min(currentHR + Double.random(in: 5...15), 165)
                if currentHR >= 160 { spikeCountdown = Int.random(in: 30...60) }
            } else {
                spikeCountdown -= 1
                currentHR = drift(current: currentHR, low: low, high: high, maxStep: 5)
            }
        } else {
            currentHR = drift(current: currentHR, low: low, high: high, maxStep: 5)
        }

        let bpm = Int(currentHR.rounded())

        // Derive RR intervals from HR with ±1% noise
        let baseRR = 60.0 / Double(bpm)
        let rrCount = Int.random(in: 3...6)
        let rrIntervals: [Double] = (0..<rrCount).map { _ in
            baseRR * Double.random(in: 0.97...1.03)
        }

        let measurement = HRMeasurement(
            heartRate: bpm,
            rrIntervals: rrIntervals,
            contactStatus: true
        )
        hrMeasurementSubject.send(measurement)
    }

    private func emitTemperature() {
        // Circadian variation: ±0.3°C over a 24h cycle, peak at 18:00
        let hour = Calendar.current.component(.hour, from: Date())
        let circadianOffset = 0.3 * sin((Double(hour) - 6.0) * .pi / 12.0)

        let coreValue = streamConfig.coreTemp + circadianOffset + Double.random(in: -0.05...0.05)
        let skinValue = streamConfig.skinTemp + circadianOffset * 0.5 + Double.random(in: -0.05...0.05)

        let coreReading = TemperatureMeasurement(
            value: coreValue,
            siteLabel: TemperatureSite.core.rawValue,
            site: .core
        )
        let skinReading = TemperatureMeasurement(
            value: skinValue,
            siteLabel: TemperatureSite.skin.rawValue,
            site: .skin
        )

        temperatureSubject.send(coreReading)
        temperatureSubject.send(skinReading)

        // EDA tracks the scenario baseline with a little sympathetic-tone noise.
        let edaValue = max(0, streamConfig.eda + Double.random(in: -0.6...0.6))
        edaSubject.send(EDAMeasurement(conductance: edaValue))
    }

    /// Smoothly drift a value within [low, high] by at most maxStep per tick.
    private func drift(current: Double, low: Double, high: Double, maxStep: Double) -> Double {
        let step = Double.random(in: -maxStep...maxStep)
        return min(max(current + step, low), high)
    }
}
