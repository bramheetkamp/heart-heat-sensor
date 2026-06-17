import Foundation
import Combine
import SwiftUI

/// User-selectable appearance. `.system` follows the device's light/dark
/// setting; the app defaults to `.dark` (see `AppEnvironment.init`).
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "Adjust to Device"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var icon: String {
        switch self {
        case .system: return "iphone"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    /// The scheme to force, or `nil` to follow the system setting.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

@MainActor
final class AppEnvironment: ObservableObject {
    let bleService: BLEService
    let dataStore: DataStore
    let demoMode: DemoModeService
    let syncService: SyncService
    let notifications: NotificationService
    let healthKit: HealthKitService
    let healthSummary: HealthSummaryService
    let dashboardLayout: DashboardLayoutService
    var router: AppRouter

    /// Bumped whenever demo data is reseeded so views can recompute derived state
    /// (warnings, recovery) that isn't already driven by SwiftData's `@Query`.
    @Published var demoDataReloadToken = UUID()

    private var cancellables = Set<AnyCancellable>()

    @Published var isDemoMode: Bool {
        didSet {
            UserDefaults.standard.set(isDemoMode, forKey: "isDemoMode")
            // Don't write demo/mock readings to Apple Health.
            bleService.healthKit = isDemoMode ? nil : healthKit
            // Begin streaming immediately when Demo Mode is switched on so data
            // flows without a manual pairing step.
            if isDemoMode, !bleService.isConnected { bleService.startScanning() }
        }
    }

    @Published var appearance: AppearanceMode {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: "appearanceMode") }
    }

    /// The currently selected companion character. Persisted to UserDefaults for
    /// instant access without an async profile load on each view render.
    @Published var selectedCharacter: MascotCharacter {
        didSet { UserDefaults.standard.set(selectedCharacter.rawValue, forKey: "selectedCharacter") }
    }

    init() {
        let isDemoMode = UserDefaults.standard.bool(forKey: "isDemoMode")
        self.isDemoMode = isDemoMode

        // Default to dark; `.system` only applies if the user explicitly picks it.
        let storedAppearance = UserDefaults.standard.string(forKey: "appearanceMode")
        self.appearance = storedAppearance.flatMap(AppearanceMode.init(rawValue:)) ?? .dark

        let storedCharacter = UserDefaults.standard.string(forKey: "selectedCharacter")
        self.selectedCharacter = storedCharacter.flatMap(MascotCharacter.init(rawValue:)) ?? .blob

        let dataStore = DataStore()
        self.dataStore = dataStore

        let demoMode = DemoModeService()
        self.demoMode = demoMode

        let transport: BLETransportProtocol
        #if targetEnvironment(simulator)
        // CoreBluetooth is unavailable on the simulator, so always use the mock
        // transport there — this lets the full pairing flow (scan → connect →
        // stream) run and produce data even without a physical device.
        let mock = MockBLETransport()
        mock.apply(config: demoMode.currentStreamConfig(for: demoMode.activeScenario))
        transport = mock
        #else
        if isDemoMode {
            let mock = MockBLETransport()
            mock.applyScenario(demoMode.activeScenario)
            transport = mock
        } else {
            transport = CoreBluetoothTransport()
        }
        #endif

        let healthKit = HealthKitService()
        self.healthKit = healthKit

        let bleService = BLEService(transport: transport, dataStore: dataStore)
        // Only write real-device readings to Health, never mock/demo data.
        if !isDemoMode { bleService.healthKit = healthKit }
        self.bleService = bleService

        self.syncService = SyncService()
        self.healthSummary = HealthSummaryService()
        self.dashboardLayout = DashboardLayoutService()

        let router = AppRouter()
        self.router = router

        let notifications = NotificationService()
        notifications.router = router
        self.notifications = notifications
        // Let the always-on heat-strain monitor post background alerts.
        bleService.notifications = notifications

        // `dashboardLayout`, `demoMode`, and `bleService` are nested
        // ObservableObjects. SwiftUI's @EnvironmentObject only observes *this*
        // object's own @Published props, so without re-broadcasting their changes
        // a dashboard reorder/hide, a scenario switch, or — crucially — a live
        // HR/temp/heat update would not re-render views bound to `env`.
        dashboardLayout.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        demoMode.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        bleService.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // Start the continuous live stream up front. On the simulator the
        // transport is always the mock, and in Demo Mode on device it's the mock
        // too — either way we want it streaming from launch so the dashboard is
        // live without the user having to walk through pairing first.
        #if targetEnvironment(simulator)
        bleService.startScanning()
        #else
        if isDemoMode { bleService.startScanning() }
        #endif
    }

    // MARK: - Demo Scenario

    /// Switch the active demo scenario end-to-end: re-point the live mock stream
    /// (so the metric cards change immediately), reseed the historical data in one
    /// transaction, and bump the reload token so derived state recomputes.
    func applyDemoScenario(_ scenario: DemoScenario) async {
        demoMode.activeScenario = scenario
        bleService.applyDemoScenario(scenario)
        // Make sure the live stream is actually running so the new scenario
        // streams continuously (it may not be if the user never paired).
        if !bleService.isConnected { bleService.startScanning() }
        try? await demoMode.seedReadings(scenario: scenario, into: dataStore)
        demoDataReloadToken = UUID()
    }
}
