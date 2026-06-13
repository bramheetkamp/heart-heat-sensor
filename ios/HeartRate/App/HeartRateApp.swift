import SwiftUI

@main
struct HeartRateApp: App {
    @StateObject private var env = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(env)
                .onOpenURL { url in
                    env.router.handle(url: url)
                }
        }
    }
}
