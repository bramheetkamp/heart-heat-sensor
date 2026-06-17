import SwiftUI
import SwiftData
import WidgetKit

struct DashboardView: View {
    @EnvironmentObject private var env: AppEnvironment
    // Bounded fetch: the newest N readings only. Without a limit this loads the
    // entire (continuously growing) table on every store change, which makes the
    // whole UI crawl. 5000 covers the warning baselines for realistic data.
    @Query private var recentReadings: [Reading]
    @State private var warnings: [HealthWarning] = []
    @State private var showScenarioPicker = false
    @State private var showCustomize = false
    @State private var profileName = ""
    @State private var eventName: String?
    @State private var eventDate: Date?
    @State private var showConfetti = false
    @State private var confettiTriggeredForScore: Int? = nil

    init() {
        var descriptor = FetchDescriptor<Reading>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 5000
        _recentReadings = Query(descriptor)
    }

    private var latestReading: Reading? { recentReadings.first }
    private var activeWarnings: [HealthWarning] { warnings.filter { $0.resolvedAt == nil } }

    // MARK: - Personalization helpers

    private var timeGreeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "Good morning" }
        if hour < 17 { return "Good afternoon" }
        return "Good evening"
    }

    private var personalizedTitle: String {
        profileName.isEmpty ? timeGreeting : "\(timeGreeting), \(profileName)"
    }

    // Consecutive days with at least one reading, counting back from today.
    private var streakDays: Int {
        guard !recentReadings.isEmpty else { return 0 }
        let calendar = Calendar.current
        let uniqueDays = Set(recentReadings.map { calendar.startOfDay(for: $0.timestamp) })
        var count = 0
        var day = calendar.startOfDay(for: Date())
        while uniqueDays.contains(day) {
            count += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return count
    }

    private var mascotState: MascotState {
        if let top = topWarning {
            switch top.type {
            case .overheating:     return .sweating
            case .gettingSick:     return .worried
            case .fatigueRecovery: return .sleepy
            }
        }
        return .happy
    }

    private var topWarning: HealthWarning? {
        warnings.filter { $0.resolvedAt == nil }.first
    }

    private var overallStatus: (text: String, color: Color) {
        guard let w = topWarning else {
            return ("All good", .green)
        }
        switch w.type {
        case .overheating:     return ("You're running hot", .red)
        case .gettingSick:     return ("Signs you may be fighting something", .orange)
        case .fatigueRecovery: return ("Recovery needed", .blue)
        }
    }

    var body: some View {
        // NOTE: no NavigationStack here — MainAppView already provides one bound
        // to env.router.path. A nested stack would swallow router pushes and
        // leave the toolbar's value-based NavigationLink with no destination.
        ZStack {
            ScrollView {
                VStack(spacing: 20) {
                    mascotStatusCard
                    ForEach(env.dashboardLayout.visibleSections) { section in
                        switch section {
                        case .aiSummary:
                            HealthSummaryCard(readings: recentReadings, warnings: warnings)
                        case .eventCountdown:
                            EventCountdownCard(eventName: eventName, eventDate: eventDate)
                        case .insights:
                            InsightsCard(readings: recentReadings, warnings: warnings)
                        case .streak:
                            StreakCard(streakDays: streakDays)
                        case .recovery:
                            RecoveryScoreCard(readings: recentReadings)
                        case .weeklyTrend:
                            WeeklyTrendCard(readings: recentReadings)
                        case .sleepQuality:
                            SleepQualityCard(readings: recentReadings)
                        case .metrics:
                            metricsGrid
                        case .warnings:
                            if !activeWarnings.isEmpty { activeWarningsSection }
                        case .quickNav:
                            quickNavRow
                        }
                    }
                }
                .padding()
            }
            .refreshable { await refresh() }
            .background(Color(.systemGroupedBackground))

            ConfettiOverlay(isActive: $showConfetti)
                .ignoresSafeArea()
        }
        .navigationTitle(personalizedTitle)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    if env.isDemoMode {
                        Button {
                            showScenarioPicker = true
                        } label: {
                            Label("Scenario", systemImage: "wand.and.stars")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.orange.opacity(0.15), in: Capsule())
                                .foregroundColor(.orange)
                        }
                    }
                    Button {
                        showCustomize = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundColor(.secondary)
                    }
                    NavigationLink(value: AppRoute.settings) {
                        Image(systemName: "gearshape.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                ConnectionStatusBadge(state: env.bleService.connectionState)
            }
        }
        .sheet(isPresented: $showScenarioPicker) {
            ScenarioPickerSheet()
                .environmentObject(env)
        }
        .sheet(isPresented: $showCustomize) {
            NavigationStack {
                CustomizeDashboardView()
                    .environmentObject(env)
            }
        }
        .task {
            // Load profile name for personalized greeting.
            if let profile = try? env.dataStore.getOrCreateProfile() {
                let stored = profile.displayName
                profileName = (stored == "User" || stored.isEmpty) ? "" : stored
                eventName = profile.eventName
                eventDate = profile.eventDate
            }
            // In demo mode with no data yet, seed the active scenario so the
            // dashboard isn't empty (e.g. demo enabled without picking a scenario).
            if env.isDemoMode && recentReadings.isEmpty {
                try? await env.demoMode.seedReadings(scenario: env.demoMode.activeScenario, into: env.dataStore)
            }
            await refresh()
        }
        // Recompute warnings/recovery after a scenario reseed. The @Query already
        // refreshes the readings + metric cards; this catches the derived state.
        .onChange(of: env.demoDataReloadToken) { _ in
            Task { await refresh() }
        }
    }

    // MARK: - Mascot + Status Card

    private var mascotStatusCard: some View {
        HStack(spacing: 20) {
            MascotView(state: mascotState, character: env.selectedCharacter, size: 80)

            VStack(alignment: .leading, spacing: 6) {
                // Character name label
                Text(env.selectedCharacter.displayName.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.orange.opacity(0.8))
                    .tracking(1.2)

                Text(overallStatus.text)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(overallStatus.color)

                Text(env.selectedCharacter.statusMessage(for: mascotState))
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.3), value: mascotState)
                    .animation(.easeInOut(duration: 0.3), value: env.selectedCharacter)
            }
            Spacer()
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
    }

    // MARK: - Metrics Grid

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
            hrCard
            coreTemperatureCard
            skinTemperatureCard
            hrvCard
            edaCard
        }
    }

    private var hrCard: some View {
        MetricCard(
            title: "Heart Rate",
            icon: "heart.fill",
            iconColor: .red
        ) {
            MetricDisplay(
                value: latestReading?.heartRate.map(Double.init),
                unit: "bpm",
                color: .red
            )
        }
        .onTapGesture {
            env.router.navigate(to: .history(metric: .heartRate))
        }
    }

    private var coreTemperatureCard: some View {
        MetricCard(
            title: "Core Temp",
            icon: "thermometer.medium",
            iconColor: .orange
        ) {
            MetricDisplay(
                value: latestReading?.tempCore,
                format: "%.1f",
                unit: "°C",
                color: .orange
            )
        }
        .onTapGesture {
            env.router.navigate(to: .history(metric: .coreTemp))
        }
    }

    private var skinTemperatureCard: some View {
        MetricCard(
            title: "Skin Temp",
            icon: "thermometer.low",
            iconColor: .yellow
        ) {
            MetricDisplay(
                value: latestReading?.tempSkin,
                format: "%.1f",
                unit: "°C",
                color: .yellow
            )
        }
        .onTapGesture {
            env.router.navigate(to: .history(metric: .skinTemp))
        }
    }

    private var hrvCard: some View {
        MetricCard(
            title: "HRV",
            icon: "waveform.path.ecg",
            iconColor: .purple
        ) {
            MetricDisplay(
                value: latestReading?.rmssd,
                format: "%.0f",
                unit: "ms",
                color: .purple
            )
        }
        .onTapGesture {
            env.router.navigate(to: .history(metric: .hrv))
        }
    }

    private var edaCard: some View {
        MetricCard(
            title: "EDA",
            icon: "drop.fill",
            iconColor: .teal
        ) {
            MetricDisplay(
                value: latestReading?.eda,
                format: "%.1f",
                unit: "µS",
                color: .teal
            )
        }
        .onTapGesture {
            env.router.navigate(to: .history(metric: .eda))
        }
    }

    // MARK: - Active Warnings

    private var activeWarningsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Active Alerts")
                .font(.headline)
                .padding(.horizontal, 4)

            ForEach(activeWarnings.prefix(3)) { warning in
                WarningRowCard(warning: warning)
                    .onTapGesture {
                        env.router.navigate(to: .warningDetail(id: warning.id))
                    }
            }

            if activeWarnings.count > 3 {
                Button("See all warnings") {
                    env.router.navigate(to: .warningDetail(id: warnings.first!.id))
                }
                .font(.footnote)
                .foregroundColor(.orange)
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Quick Navigation Row

    private var quickNavRow: some View {
        HStack(spacing: 12) {
            QuickNavButton(
                icon: "figure.run",
                label: "Workout"
            ) {
                env.router.navigate(to: .workout)
            }
            QuickNavButton(
                icon: "chart.xyaxis.line",
                label: "History"
            ) {
                env.router.navigate(to: .history(metric: .heartRate))
            }
            QuickNavButton(
                icon: "exclamationmark.triangle.fill",
                label: "Alerts",
                badge: activeWarnings.count
            ) {
                if let first = warnings.first {
                    env.router.navigate(to: .warningDetail(id: first.id))
                }
            }
            QuickNavButton(
                icon: "antenna.radiowaves.left.and.right",
                label: "Pair"
            ) {
                env.router.navigate(to: .pair)
            }
        }
    }

    // MARK: - Actions

    private func refresh() async {
        warnings = WarningsEngine.compute(
            readings: recentReadings,
            profile: (try? env.dataStore.getOrCreateProfile()) ?? UserProfile()
        )
        await env.notifications.notifyIfNeeded(for: warnings)
        await env.notifications.checkAndNotifyStreak(days: streakDays, character: env.selectedCharacter)

        // Re-schedule morning briefing with the latest recovery score so the
        // notification content stays fresh even if the user's baseline shifts.
        let recoveryResult = RecoveryScoreCard.compute(readings: recentReadings)
        let recoveryScore: Int? = { if case .score(let s, _, _) = recoveryResult { return s }; return nil }()
        await env.notifications.scheduleMorningBriefing(score: recoveryScore, character: env.selectedCharacter)

        // Persist recovery score to App Group so the homescreen widget stays current.
        let ud = UserDefaults(suiteName: "group.com.heartrate.app") ?? .standard
        if let score = recoveryScore { ud.set(score, forKey: "cachedRecoveryScore") }
        WidgetCenter.shared.reloadAllTimelines()

        // Fire confetti once per unique excellent score so it doesn't repeat on every refresh.
        if let score = recoveryScore, score >= 82, confettiTriggeredForScore != score {
            confettiTriggeredForScore = score
            showConfetti = true
        }
    }
}

#Preview {
    DashboardView()
        .environmentObject(AppEnvironment())
}
