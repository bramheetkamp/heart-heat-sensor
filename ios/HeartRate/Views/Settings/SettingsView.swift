import SwiftUI
import SwiftData

struct SettingsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var profile: UserProfile?
    @State private var showDemoConfirm = false
    @State private var showResetConfirm = false
    @State private var backendURL = ProcessInfo.processInfo.environment["API_BASE_URL"] ?? "http://localhost:3100"

    var body: some View {
        List {
            demoSection
            thresholdsSection
            connectionSection
            backendSection
            aboutSection
        }
        .navigationTitle("Settings")
        .task { profile = try? env.dataStore.getOrCreateProfile() }
    }

    // MARK: - Sections

    private var demoSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { env.isDemoMode },
                set: { newVal in
                    env.isDemoMode = newVal
                    UserDefaults.standard.set(newVal, forKey: "isDemoMode")
                    if newVal {
                        Task { try? await env.demoMode.seedReadings(scenario: env.demoMode.activeScenario, into: env.dataStore) }
                    }
                }
            )) {
                Label("Demo Mode", systemImage: "wand.and.stars")
            }
            .tint(.orange)

            if env.isDemoMode {
                NavigationLink {
                    ScenarioPicker()
                        .environmentObject(env)
                } label: {
                    HStack {
                        Label("Active Scenario", systemImage: "play.circle")
                        Spacer()
                        Text(env.demoMode.activeScenario.rawValue)
                            .foregroundColor(.secondary)
                    }
                }
            }
        } header: {
            Text("Demo & Testing")
        } footer: {
            Text("Demo mode feeds simulated data through the same pipeline as a real device. Great for testing all features.")
        }
    }

    private var thresholdsSection: some View {
        Section("Alert Thresholds") {
            if let p = profile {
                ThresholdRow(
                    label: "Overheating (core temp)",
                    value: Binding(get: { p.overheatingThreshold }, set: { p.overheatingThreshold = $0 }),
                    unit: "°C",
                    range: 37.5...40.0,
                    step: 0.1,
                    format: "%.1f"
                )
                ThresholdRow(
                    label: "Sick: HR above baseline",
                    value: Binding(get: { p.sickHRThreshold }, set: { p.sickHRThreshold = $0 }),
                    unit: "bpm",
                    range: 3...15,
                    step: 1,
                    format: "%.0f"
                )
                ThresholdRow(
                    label: "Sick: temp above baseline",
                    value: Binding(get: { p.sickTempThreshold }, set: { p.sickTempThreshold = $0 }),
                    unit: "°C",
                    range: 0.1...1.0,
                    step: 0.05,
                    format: "%.2f"
                )
            } else {
                ProgressView()
            }
        }
    }

    private var connectionSection: some View {
        Section("Device") {
            HStack {
                Label("Status", systemImage: "antenna.radiowaves.left.and.right")
                Spacer()
                ConnectionStatusBadge(state: env.bleService.connectionState)
            }
            Button {
                env.bleService.startScanning()
            } label: {
                Label("Scan for Device", systemImage: "magnifyingglass")
            }
            .disabled(env.isDemoMode)
        }
    }

    private var backendSection: some View {
        Section("Backend Sync") {
            if let p = profile, let token = p.backendToken {
                HStack {
                    Label("Account", systemImage: "person.circle")
                    Spacer()
                    Text(p.email ?? "Connected")
                        .foregroundColor(.secondary)
                }
                Button(role: .destructive) {
                    p.backendToken = nil
                    p.backendUserId = nil
                    try? env.dataStore.container.mainContext.save()
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .disabled(token.isEmpty)
            } else {
                NavigationLink("Sign in / Create Account") {
                    AccountSetupView()
                        .environmentObject(env)
                }
            }

            HStack {
                Label("Server URL", systemImage: "server.rack")
                Spacer()
                Text(backendURL)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            HStack {
                Text("Version")
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    .foregroundColor(.secondary)
            }
            Link(destination: URL(string: "https://github.com/bramheetkamp/heart-heat-sensor")!) {
                Label("GitHub", systemImage: "link")
            }
            Button(role: .destructive) {
                showResetConfirm = true
            } label: {
                Label("Reset All Data", systemImage: "trash")
            }
            .confirmationDialog("Reset All Data?", isPresented: $showResetConfirm, titleVisibility: .visible) {
                Button("Reset", role: .destructive) {
                    UserDefaults.standard.removeObject(forKey: "onboardingComplete")
                    // Full data reset would cascade-delete all readings
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will delete all local readings and return to onboarding.")
            }
        }
    }
}

// MARK: - Supporting Views

private struct ThresholdRow: View {
    let label: String
    @Binding var value: Double
    let unit: String
    let range: ClosedRange<Double>
    let step: Double
    let format: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.system(size: 14))
                Spacer()
                Text("\(String(format: format, value)) \(unit)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.orange)
                    .monospacedDigit()
            }
            Slider(value: $value, in: range, step: step)
                .tint(.orange)
        }
        .padding(.vertical, 4)
    }
}

private struct ScenarioPicker: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(DemoScenario.allCases) { scenario in
            Button {
                env.demoMode.activeScenario = scenario
                Task { try? await env.demoMode.seedReadings(scenario: scenario, into: env.dataStore) }
                dismiss()
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(scenario.rawValue).font(.headline).foregroundColor(.primary)
                        Text(scenario.description).font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    if env.demoMode.activeScenario == scenario {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.orange)
                    }
                }
            }
        }
        .navigationTitle("Choose Scenario")
    }
}

private struct AccountSetupView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                TextField("Email", text: $email).keyboardType(.emailAddress).autocapitalization(.none)
                SecureField("Password", text: $password)
            }
            if let error { Text(error).foregroundColor(.red).font(.caption) }
            Section {
                Button("Create Account") { Task { await register() } }.disabled(isLoading)
                Button("Sign In") { Task { await login() } }.disabled(isLoading)
            }
        }
        .navigationTitle("Account")
        .overlay(isLoading ? ProgressView() : nil)
    }

    private func register() async {
        isLoading = true; defer { isLoading = false }
        do {
            let token = try await env.syncService.register(email: email, password: password)
            let profile = try env.dataStore.getOrCreateProfile()
            profile.email = email; profile.backendToken = token
            try env.dataStore.container.mainContext.save()
            dismiss()
        } catch { self.error = error.localizedDescription }
    }

    private func login() async {
        isLoading = true; defer { isLoading = false }
        do {
            let token = try await env.syncService.login(email: email, password: password)
            let profile = try env.dataStore.getOrCreateProfile()
            profile.email = email; profile.backendToken = token
            try env.dataStore.container.mainContext.save()
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
