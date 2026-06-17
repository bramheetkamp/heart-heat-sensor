import SwiftUI
import SwiftData
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var profile: UserProfile?
    @State private var showDemoConfirm = false
    @State private var showResetConfirm = false
    @State private var showExport = false
    @State private var backendURL = ProcessInfo.processInfo.environment["API_BASE_URL"] ?? "http://localhost:3100"

    var body: some View {
        List {
            companionSection
            eventSection
            dashboardSection
            appearanceSection
            demoSection
            healthKitSection
            notificationsSection
            thresholdsSection
            connectionSection
            backendSection
            aboutSection
        }
        .navigationTitle("Settings")
        .task { profile = try? env.dataStore.getOrCreateProfile() }
        // Pick up an edited heat-caution threshold in the always-on monitor.
        .onDisappear { env.bleService.refreshHeatThreshold() }
    }

    // MARK: - Sections

    private var companionSection: some View {
        Section {
            NavigationLink {
                CharacterGalleryView()
                    .environmentObject(env)
            } label: {
                HStack(spacing: 14) {
                    MascotView(state: .happy, character: env.selectedCharacter, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(env.selectedCharacter.displayName)
                            .font(.system(size: 15, weight: .semibold))
                        Text("Tap to change companion or AI tone")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("Companion")
        } footer: {
            Text("Unlock new companions by recording more health data. Customize how your AI talks to you.")
        }
    }

    private var dashboardSection: some View {
        Section {
            NavigationLink {
                CustomizeDashboardView()
                    .environmentObject(env)
            } label: {
                Label("Customize Dashboard", systemImage: "slider.horizontal.3")
            }
        } header: {
            Text("Dashboard")
        } footer: {
            Text("Choose which sections to show and drag them into your preferred order.")
        }
    }

    private var appearanceSection: some View {
        Section {
            Picker(selection: Binding(
                get: { env.appearance },
                set: { env.appearance = $0 }
            )) {
                ForEach(AppearanceMode.allCases) { mode in
                    Label(mode.label, systemImage: mode.icon).tag(mode)
                }
            } label: {
                Label("Appearance", systemImage: "circle.lefthalf.filled")
            }
            .pickerStyle(.navigationLink)
        } header: {
            Text("Appearance")
        } footer: {
            Text("Dark is the default. Choose \"Adjust to Device\" to follow your system light/dark setting.")
        }
    }

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

    private var healthKitSection: some View {
        Section {
            if !HealthKitService.available {
                Label("Not available on this device", systemImage: "heart.slash")
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    Label("Apple Health", systemImage: "heart.fill")
                        .foregroundStyle(.red)
                    Spacer()
                    Text(healthKitStatusLabel)
                        .font(.footnote)
                        .foregroundStyle(healthKitStatusColor)
                }

                switch env.healthKit.authorizationStatus {
                case .sharingAuthorized:
                    Toggle(isOn: Binding(
                        get: { env.healthKit.isEnabled },
                        set: { env.healthKit.isEnabled = $0 }
                    )) {
                        Label("Write to Health App", systemImage: "waveform.path.ecg")
                    }
                    .tint(.orange)

                case .sharingDenied:
                    Label("Re-enable in Settings › Health › Pulse", systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                default:
                    Button {
                        Task { await env.healthKit.requestAuthorization() }
                    } label: {
                        Label("Connect to Apple Health", systemImage: "heart.circle")
                    }
                }
            }
        } header: {
            Text("Apple Health")
        } footer: {
            Text("When connected, each live reading (heart rate, body temperature, HRV) is written to Apple Health in real time. Demo data is never synced.")
        }
        .task { env.healthKit.refreshStatus() }
    }

    private var healthKitStatusLabel: String {
        switch env.healthKit.authorizationStatus {
        case .sharingAuthorized: return env.healthKit.isEnabled ? "Writing" : "Connected"
        case .sharingDenied:     return "Denied"
        default:                 return "Not connected"
        }
    }

    private var healthKitStatusColor: Color {
        switch env.healthKit.authorizationStatus {
        case .sharingAuthorized: return env.healthKit.isEnabled ? .green : .secondary
        case .sharingDenied:     return .red
        default:                 return .secondary
        }
    }

    private var notificationsSection: some View {
        Section {
            HStack {
                Label("Status", systemImage: "bell.fill")
                Spacer()
                Text(notificationStatusLabel)
                    .font(.footnote)
                    .foregroundStyle(notificationStatusColor)
            }

            if env.notifications.authorizationStatus != .authorized {
                Button {
                    Task { await env.notifications.requestAuthorization() }
                } label: {
                    Label("Enable Notifications", systemImage: "bell.badge")
                }
            }

            Toggle(isOn: Binding(
                get: { UserDefaults.standard.bool(forKey: "morningBriefingEnabled") },
                set: { enabled in
                    UserDefaults.standard.set(enabled, forKey: "morningBriefingEnabled")
                    if !enabled {
                        UNUserNotificationCenter.current()
                            .removePendingNotificationRequests(withIdentifiers: ["morning_briefing"])
                    }
                }
            )) {
                Label("Morning Briefing", systemImage: "sunrise.fill")
            }
            .tint(.orange)
            .disabled(env.notifications.authorizationStatus != .authorized)
        } header: {
            Text("Notifications")
        } footer: {
            Text("Morning Briefing fires at 8 AM with your recovery score, voiced by \(env.selectedCharacter.displayName). Health alerts and streak milestones are always sent when notifications are allowed.")
        }
        .task { await env.notifications.refreshStatus() }
    }

    private var notificationStatusLabel: String {
        switch env.notifications.authorizationStatus {
        case .authorized:    return "Allowed"
        case .denied:        return "Denied"
        case .provisional:   return "Provisional"
        default:             return "Not set"
        }
    }

    private var notificationStatusColor: Color {
        switch env.notifications.authorizationStatus {
        case .authorized:  return .green
        case .denied:      return .red
        default:           return .secondary
        }
    }

    private var eventSection: some View {
        Section {
            if let p = profile {
                TextField("Event name (e.g. City Marathon)",
                          text: Binding(
                            get: { p.eventName ?? "" },
                            set: { p.eventName = $0.isEmpty ? nil : $0 }))

                Toggle("Set a date", isOn: Binding(
                    get: { p.eventDate != nil },
                    set: { on in
                        if on {
                            if p.eventDate == nil {
                                p.eventDate = Calendar.current.date(byAdding: .day, value: 30, to: Date())
                            }
                        } else {
                            p.eventDate = nil
                        }
                    }))

                if p.eventDate != nil {
                    DatePicker("Event date",
                               selection: Binding(
                                get: { p.eventDate ?? Date() },
                                set: { p.eventDate = $0 }),
                               in: Date()...,
                               displayedComponents: .date)
                }
            } else {
                ProgressView()
            }
        } header: {
            Text("Target Event")
        } footer: {
            Text("Shown as a countdown on your dashboard. Add the Event Countdown card via Customize Dashboard.")
        }
    }

    private var thresholdsSection: some View {
        Section("Alert Thresholds") {
            if let p = profile {
                ThresholdRow(
                    label: "Heat caution (core temp)",
                    value: Binding(get: { p.overheatingThreshold }, set: { p.overheatingThreshold = $0 }),
                    unit: "°C",
                    range: 37.5...40.0,
                    step: 0.1,
                    format: "%.1f"
                )
                Text(String(format: "Workout alerts escalate at caution %.1f → serious %.1f → STOP %.1f °C.",
                            p.overheatingThreshold,
                            HeatStrainEngine.seriousThreshold(caution: p.overheatingThreshold),
                            HeatStrainEngine.criticalThreshold(caution: p.overheatingThreshold)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
            Button {
                showExport = true
            } label: {
                Label("Export Data as CSV", systemImage: "square.and.arrow.up")
            }
            .sheet(isPresented: $showExport) {
                ExportDataView()
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
