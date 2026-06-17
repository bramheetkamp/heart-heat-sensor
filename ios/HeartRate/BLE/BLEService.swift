import Foundation
import Combine
import UIKit
import WidgetKit

// MARK: - BLEService

@MainActor
final class BLEService: ObservableObject {

    // MARK: - Published State

    @Published var connectionState: BLEConnectionState = .disconnected
    @Published var latestHR: HRMeasurement?
    @Published var latestTemp: [TemperatureSite: TemperatureMeasurement] = [:]
    @Published var latestEDA: EDAMeasurement?
    @Published var isConnected: Bool = false

    /// Always-on heat-strain assessment, recomputed on every core-temp sample
    /// from the connected sensor — independent of whether `WorkoutView` is open.
    /// This is what makes overheating warnings fire even when the user started a
    /// run elsewhere and never opened Pulse.
    @Published private(set) var heatAssessment: HeatStrainEngine.Assessment =
        HeatStrainEngine.assess(samples: [], isActive: false, caution: 38.5)
    /// Recent core-temp samples (trailing window) for the live workout trend chart.
    @Published private(set) var heatTrend: [HeatStrainEngine.Sample] = []

    // MARK: - Private

    private let transport: BLETransportProtocol
    private let dataStore: DataStore?
    var healthKit: HealthKitService?
    /// Set by AppEnvironment so background heat alerts can be posted.
    weak var notifications: NotificationService?
    private var cancellables = Set<AnyCancellable>()
    private let hapticGenerator = UINotificationFeedbackGenerator()
    private let impactGenerator = UIImpactFeedbackGenerator(style: .heavy)

    /// Cached caution threshold (`profile.overheatingThreshold`). Refreshed lazily
    /// and whenever Settings change it via `refreshHeatThreshold()`.
    private var cautionThreshold: Double = 38.5
    private var cautionLoaded = false
    /// Rolling window of core-temp samples kept for assessment + the trend chart.
    private var heatSamples: [HeatStrainEngine.Sample] = []
    private static let heatWindow: TimeInterval = 900   // 15 min

    /// Live-sample counter; we prune old rows every so often rather than on each
    /// save to keep the hot path cheap. ~180 days kept (well past warning baselines).
    private var liveSampleCount = 0
    private static let pruneEveryNSamples = 240   // ≈ every 20 min at a 5 s cadence
    private static let retentionDays = 180

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

    /// Re-point the live demo stream at a new scenario so the on-screen metric
    /// cards (driven by the newest persisted Reading) reflect the picked scenario
    /// immediately. No-op for a real `CoreBluetoothTransport`.
    func applyDemoScenario(_ scenario: DemoScenario) {
        (transport as? MockBLETransport)?.applyScenario(scenario)
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

        transport.edaPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] measurement in
                self?.latestEDA = measurement
            }
            .store(in: &cancellables)
    }

    // MARK: - Live Persistence

    /// Persist a combined snapshot of the latest live measurements as a Reading,
    /// so a connected device (real or, on the simulator, the mock) populates the
    /// data store that the dashboard and history read from.
    ///
    /// HR is optional: the BodyTempSensor (Profile B) streams temperature + EDA
    /// only and has no heart-rate sensor, so a Reading is still persisted from
    /// temperature/EDA alone. Activity can only be inferred when HR is present.
    private func persistLiveSample() {
        guard let dataStore, isConnected else { return }

        // Require at least one real signal so we never write empty rows.
        let hr = latestHR
        let tempCore = latestTemp[.core]?.value
        let tempSkin = latestTemp[.skin]?.value
        let eda = latestEDA?.conductance
        guard hr != nil || tempCore != nil || tempSkin != nil || eda != nil else { return }

        let deviceName: String
        if case .connected(let name) = connectionState { deviceName = name } else { deviceName = "LIVE" }

        let activity: Reading.ActivityLevel
        if let hr {
            let hour = Calendar.current.component(.hour, from: Date())
            let isLikelySleeping = (hour >= 22 || hour < 7) && hr.heartRate < 65
            if hr.heartRate >= 100 {
                activity = .active
            } else if isLikelySleeping {
                activity = .sleep
            } else {
                activity = .rest
            }
        } else { activity = .unknown }

        let reading = Reading(
            timestamp: Date(),
            heartRate: hr?.heartRate,
            rrIntervals: hr?.rrIntervals ?? [],
            tempCore: tempCore,
            tempSkin: tempSkin,
            eda: eda,
            activity: activity,
            deviceId: deviceName
        )
        try? dataStore.save(reading: reading)

        // Always-on heat-strain evaluation: assess every core-temp sample and
        // fire escalating alerts even if no workout was started in-app.
        if let core = tempCore {
            evaluateHeatStrain(coreTemp: core, isActive: activity == .active, at: reading.timestamp)
        }

        // Write latest vitals to the App Group suite so the homescreen widget
        // and Siri App Intents can read them without opening the app.
        let ud = UserDefaults(suiteName: "group.com.heartrate.app") ?? .standard
        if let hrValue = hr?.heartRate { ud.set(hrValue, forKey: "cachedHR") }
        if let core = tempCore { ud.set(core, forKey: "cachedCoreTemp") }
        ud.set(Date().timeIntervalSince1970, forKey: "cachedReadingAt")
        WidgetCenter.shared.reloadAllTimelines()

        if let hk = healthKit {
            Task { await hk.write(reading) }
        }

        liveSampleCount += 1
        if liveSampleCount % BLEService.pruneEveryNSamples == 0 {
            try? dataStore.pruneReadings(olderThan: BLEService.retentionDays)
        }
    }

    // MARK: - Always-on Heat Strain

    /// Reload the caution threshold from the user profile (call after Settings change).
    func refreshHeatThreshold() {
        if let p = try? dataStore?.getOrCreateProfile() {
            cautionThreshold = p.overheatingThreshold
            cautionLoaded = true
        }
    }

    /// Clear the rolling heat buffer and reset the live assessment to nominal.
    /// Called on a demo-scenario switch so a previous (e.g. overheating) session's
    /// samples don't linger and keep the banner/mascot hot after switching back.
    func resetHeatMonitor() {
        heatSamples.removeAll()
        heatAssessment = HeatStrainEngine.assess(samples: [], isActive: false, caution: cautionThreshold)
        heatTrend = []
        notifications?.resetHeatStrainAlerts()
    }

    /// Assess one core-temp sample, publish the result, and post a heat alert
    /// when it escalates. `notifyHeatStrain` self-throttles (re-fires only on a
    /// higher level; calling it at lower levels lowers the throttle baseline so a
    /// later episode re-alerts), so it's safe to call on every sample.
    private func evaluateHeatStrain(coreTemp: Double, isActive: Bool, at time: Date) {
        if !cautionLoaded { refreshHeatThreshold() }

        heatSamples.append(.init(time: time, core: coreTemp))
        let windowStart = time.addingTimeInterval(-BLEService.heatWindow)
        heatSamples.removeAll { $0.time < windowStart }

        let assessment = HeatStrainEngine.assess(
            samples: heatSamples, isActive: isActive, caution: cautionThreshold, now: time)
        let previous = heatAssessment.level
        heatAssessment = assessment
        heatTrend = heatSamples

        // Haptics (foreground only — no-op when backgrounded) on escalation.
        if assessment.level > previous {
            switch assessment.level {
            case .critical: hapticGenerator.notificationOccurred(.error)
            case .serious:  hapticGenerator.notificationOccurred(.warning)
            case .elevated: impactGenerator.impactOccurred()
            case .nominal:  break
            }
        }
        if assessment.level == .critical { impactGenerator.impactOccurred(intensity: 1.0) }

        // Local notification — the mechanism that reaches the user with the app closed.
        if let notifications {
            let level = assessment.level
            let message = assessment.message
            Task { await notifications.notifyHeatStrain(level: level, message: message) }
        }
    }
}
