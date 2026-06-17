import SwiftUI
import AppIntents

@main
struct HeartRateApp: App {
    @StateObject private var env = AppEnvironment()

    init() {
        // Register Siri App Shortcuts so "Hey Siri, what's my heart rate?"
        // works without requiring the user to manually add the shortcut.
        PulseShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(env)
                // Expose the router as its own observable so views that bind to
                // router.path (the NavigationStack) re-render when it changes
                // programmatically — deep links and router.navigate(). Without
                // this, only NavigationLink(value:) taps would actually navigate.
                .environmentObject(env.router)
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
