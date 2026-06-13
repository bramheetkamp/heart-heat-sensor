import SwiftUI

struct RootView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var onboardingComplete = UserDefaults.standard.bool(forKey: "onboardingComplete")

    var body: some View {
        Group {
            if onboardingComplete {
                MainAppView()
            } else {
                OnboardingView()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .onboardingComplete)) { _ in
            withAnimation(.easeInOut) { onboardingComplete = true }
        }
    }
}

struct MainAppView: View {
    @EnvironmentObject private var env: AppEnvironment

    var body: some View {
        NavigationStack(path: $env.router.path) {
            DashboardView()
                .navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case .dashboard:
                        DashboardView()
                    case .history(let metric):
                        HistoryView(metric: metric)
                    case .warningDetail(let id):
                        WarningDetailView(warningId: id)
                    case .settings:
                        SettingsView()
                    case .pair:
                        PairingStep()
                    }
                }
        }
        .sheet(item: $env.router.presentedSheet) { sheet in
            switch sheet {
            case .onboarding:
                OnboardingView()
            case .scenarioPicker:
                ScenarioPickerSheet()
            }
        }
        .tint(.orange)
        .task { await env.notifications.requestAuthorization() }
    }
}
