import Foundation
import Combine

@MainActor
final class AppEnvironment: ObservableObject {
    let bleService: BLEService
    let dataStore: DataStore
    let demoMode: DemoModeService
    let syncService: SyncService
    let notifications: NotificationService
    var router: AppRouter

    @Published var isDemoMode: Bool {
        didSet { UserDefaults.standard.set(isDemoMode, forKey: "isDemoMode") }
    }

    init() {
        let isDemoMode = UserDefaults.standard.bool(forKey: "isDemoMode")
        self.isDemoMode = isDemoMode

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

        let router = AppRouter()
        self.router = router

        let notifications = NotificationService()
        notifications.router = router
        self.notifications = notifications
    }
}
