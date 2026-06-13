import SwiftUI

@main
struct HeartRateApp: App {
    @StateObject private var env = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(env)
                // Force the user-selected appearance app-wide (defaults to dark).
                // `.system` maps to nil, which lets the device setting through.
                .preferredColorScheme(env.appearance.colorScheme)
                // @Query in DashboardView/HistoryView reads from the environment's
                // model container — point it at the same store DataStore writes to,
                // otherwise queried data (incl. demo readings) never appears.
                .modelContainer(env.dataStore.container)
                .onOpenURL { url in
                    env.router.handle(url: url)
                }
        }
    }
}
