import Foundation
import HealthKit

// MARK: - HealthKitService

/// Bridges live BLE readings into Apple Health. Writes heart rate, body
/// temperature (core), and HRV (RMSSD) on every cadence tick from BLEService.
/// Authorization is explicit — the user opts in from Settings — and the service
/// is a no-op on devices where HealthKit is unavailable (e.g. simulator).
@MainActor
final class HealthKitService: ObservableObject {

    static let available = HKHealthStore.isHealthDataAvailable()

    @Published private(set) var authorizationStatus: HKAuthorizationStatus = .notDetermined

    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "healthKitEnabled") }
    }

    private let store = HKHealthStore()

    private static let hrType: HKQuantityType   = HKQuantityType.quantityType(forIdentifier: .heartRate)!
    private static let tmpType: HKQuantityType  = HKQuantityType.quantityType(forIdentifier: .bodyTemperature)!
    private static let hrvType: HKQuantityType  = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!
    private static let shareTypes: Set<HKSampleType> = [hrType, tmpType, hrvType]

    init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: "healthKitEnabled")
        refreshStatus()
    }

    // MARK: - Authorization

    func requestAuthorization() async {
        guard Self.available else { return }
        _ = try? await store.requestAuthorization(toShare: Self.shareTypes, read: [])
        refreshStatus()
    }

    func refreshStatus() {
        guard Self.available else { return }
        authorizationStatus = store.authorizationStatus(for: Self.hrType)
    }

    // MARK: - Write

    /// Writes available sensor values from a Reading to Apple Health.
    /// Silent no-op when not available, not enabled, or not authorized.
    func write(_ reading: Reading) async {
        guard Self.available,
              isEnabled,
              authorizationStatus == .sharingAuthorized else { return }

        var samples: [HKObject] = []
        let date = reading.timestamp

        if let hr = reading.heartRate {
            let qty = HKQuantity(
                unit: HKUnit.count().unitDivided(by: .minute()),
                doubleValue: Double(hr)
            )
            samples.append(HKQuantitySample(
                type: Self.hrType, quantity: qty, start: date, end: date
            ))
        }

        if let temp = reading.tempCore {
            let qty = HKQuantity(unit: .degreeCelsius(), doubleValue: temp)
            samples.append(HKQuantitySample(
                type: Self.tmpType, quantity: qty, start: date, end: date
            ))
        }

        // RMSSD is in milliseconds; HealthKit HRV SDNN unit is also ms.
        if let rmssd = reading.rmssd {
            let qty = HKQuantity(unit: HKUnit(from: "ms"), doubleValue: rmssd)
            samples.append(HKQuantitySample(
                type: Self.hrvType, quantity: qty, start: date, end: date
            ))
        }

        guard !samples.isEmpty else { return }
        try? await store.save(samples)
    }
}
