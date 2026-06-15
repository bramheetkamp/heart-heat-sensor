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
    let healthSummary: HealthSummaryService
    var router: AppRouter

    @Published var isDemoMode: Bool {
        didSet { UserDefaults.standard.set(isDemoMode, forKey: "isDemoMode") }
    }

    @Published var appearance: AppearanceMode {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: "appearanceMode") }
    }

    init() {
        let isDemoMode = UserDefaults.standard.bool(forKey: "isDemoMode")
        self.isDemoMode = isDemoMode

        // Default to dark; `.system` only applies if the user explicitly picks it.
        let storedAppearance = UserDefaults.standard.string(forKey: "appearanceMode")
        self.appearance = storedAppearance.flatMap(AppearanceMode.init(rawValue:)) ?? .dark

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

        self.bleService = BLEService(transport: transport, dataStore: dataStore)
        self.syncService = SyncService()
        self.healthSummary = HealthSummaryService()

        let router = AppRouter()
        self.router = router

        let notifications = NotificationService()
        notifications.router = router
        self.notifications = notifications
    }
}
