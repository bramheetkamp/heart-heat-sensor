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
        if isDemoMode {
            let mock = MockBLETransport()
            mock.applyScenario(demoMode.activeScenario)
            transport = mock
        } else {
            transport = CoreBluetoothTransport()
        }

        self.bleService = BLEService(transport: transport)
        self.syncService = SyncService()

        let router = AppRouter()
        self.router = router

        let notifications = NotificationService()
        notifications.router = router
        self.notifications = notifications
    }
}
