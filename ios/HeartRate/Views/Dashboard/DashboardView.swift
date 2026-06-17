import SwiftUI
import SwiftData

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
        ScrollView {
            VStack(spacing: 20) {
                mascotStatusCard
                ForEach(env.dashboardLayout.visibleSections) { section in
                    switch section {
                    case .aiSummary:
                        HealthSummaryCard(readings: Array(recentReadings), warnings: warnings)
                    case .streak:
                        streakCard
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
            }
            // In demo mode with no data yet, seed the active scenario so the
            // dashboard isn't empty (e.g. demo enabled without picking a scenario).
            if env.isDemoMode && recentReadings.isEmpty {
                try? await env.demoMode.seedReadings(scenario: env.demoMode.activeScenario, into: env.dataStore)
            }
            await refresh()
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

    // MARK: - Streak Card

    private var streakCard: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(streakDays > 0 ? Color.orange.opacity(0.12) : Color(.systemGray6))
                    .frame(width: 50, height: 50)
                Image(systemName: streakDays > 0 ? "flame.fill" : "flame")
                    .font(.system(size: 22))
                    .foregroundStyle(streakDays > 0 ? .orange : Color(.systemGray3))
            }

            VStack(alignment: .leading, spacing: 2) {
                if streakDays > 0 {
                    Text("\(streakDays) day\(streakDays == 1 ? "" : "s") in a row")
                        .font(.system(size: 15, weight: .semibold))
                    Text(streakSubtitle(for: streakDays))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Start your streak")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Wear your sensor today to begin.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if streakDays > 0 {
                streakMilestoneRing
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }

    private var streakMilestoneRing: some View {
        let milestone = nextStreakMilestone(from: streakDays)
        let base = previousStreakMilestone(from: streakDays)
        let span = max(milestone - base, 1)
        let progress = Double(streakDays - base) / Double(span)

        return VStack(spacing: 3) {
            ZStack {
                Circle()
                    .stroke(Color(.systemGray5), lineWidth: 3.5)
                Circle()
                    .trim(from: 0, to: min(progress, 1.0))
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.6), value: streakDays)
                VStack(spacing: 0) {
                    Text("\(milestone)")
                        .font(.system(size: 11, weight: .bold))
                        .monospacedDigit()
                    Text("d")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 40, height: 40)
            Text("goal")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }

    private func nextStreakMilestone(from days: Int) -> Int {
        [7, 14, 30, 60, 90, 180].first { $0 > days } ?? 180
    }

    private func previousStreakMilestone(from days: Int) -> Int {
        ([0, 7, 14, 30, 60, 90] as [Int]).last { $0 <= days } ?? 0
    }

    private func streakSubtitle(for days: Int) -> String {
        let next = nextStreakMilestone(from: days)
        switch days {
        case 7:  return "One week — Hoot the Owl is unlocked! 🦉"
        case 14: return "Two weeks — your baseline is forming nicely."
        case 30: return "A month! Ember the Fox is unlocked 🦊"
        default:
            let remaining = next - days
            if days < 7  { return "\(remaining) more day\(remaining == 1 ? "" : "s") to unlock Hoot the Owl." }
            if days < 30 { return "\(remaining) day\(remaining == 1 ? "" : "s") to unlock Ember the Fox." }
            return "\(remaining) day\(remaining == 1 ? "" : "s") to your next milestone."
        }
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
            readings: Array(recentReadings),
            profile: (try? env.dataStore.getOrCreateProfile()) ?? UserProfile()
        )
        await env.notifications.notifyIfNeeded(for: warnings)
    }
}

// MARK: - Supporting Components

struct MetricCard<Content: View>: View {
    let title: String
    let icon: String
    let iconColor: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(iconColor)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
            }
            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }
}

struct WarningRowCard: View {
    let warning: HealthWarning

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: warning.type.icon)
                .font(.system(size: 20))
                .foregroundColor(warning.type.color)
                .frame(width: 36, height: 36)
                .background(warning.type.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(warning.title)
                    .font(.system(size: 15, weight: .semibold))
                Text(warning.message)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(warning.type.color.opacity(0.2), lineWidth: 1)
        )
    }
}

private struct QuickNavButton: View {
    let icon: String
    let label: String
    var badge: Int = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: icon)
                        .font(.system(size: 22))
                        .foregroundColor(.orange)
                        .frame(width: 44, height: 44)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

                    if badge > 0 {
                        Text("\(badge)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(3)
                            .background(Color.red, in: Circle())
                            .offset(x: 6, y: -6)
                    }
                }
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(.background, in: RoundedRectangle(cornerRadius: 16))
        }
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
    }
}

// MARK: - Scenario Picker Sheet

struct ScenarioPickerSheet: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(DemoScenario.allCases) { scenario in
                Button {
                    env.demoMode.activeScenario = scenario
                    Task { try? await env.demoMode.seedReadings(scenario: scenario, into: env.dataStore) }
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(scenario.rawValue).font(.headline)
                        Text(scenario.description).font(.footnote).foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Demo Scenario")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    DashboardView()
        .environmentObject(AppEnvironment())
}
