import SwiftUI

struct WarningsListView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var warnings: [HealthWarning] = []
    @State private var showResolved = false

    private var active: [HealthWarning]   { warnings.filter { $0.resolvedAt == nil } }
    private var resolved: [HealthWarning] { warnings.filter { $0.resolvedAt != nil } }

    var body: some View {
        List {
            if active.isEmpty && !showResolved {
                Section {
                    VStack(spacing: 16) {
                        MascotView(state: .happy, size: 70)
                        Text("All clear")
                            .font(.headline)
                        Text("No active alerts. Your body's doing great.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
                .listRowBackground(Color.clear)
            }

            if !active.isEmpty {
                Section("Active") {
                    ForEach(active) { w in
                        NavigationLink(value: AppRoute.warningDetail(id: w.id)) {
                            WarningRow(warning: w)
                        }
                    }
                }
            }

            if !resolved.isEmpty {
                Section {
                    Button(showResolved ? "Hide resolved" : "Show \(resolved.count) resolved") {
                        withAnimation { showResolved.toggle() }
                    }
                    .font(.footnote)
                    .foregroundColor(.secondary)
                }
                .listRowBackground(Color.clear)

                if showResolved {
                    Section("Resolved") {
                        ForEach(resolved) { w in
                            NavigationLink(value: AppRoute.warningDetail(id: w.id)) {
                                WarningRow(warning: w)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Alerts")
        .task { loadWarnings() }
    }

    private func loadWarnings() {
        guard let profile = try? env.dataStore.getOrCreateProfile(),
              let readings = try? env.dataStore.recentReadings(days: 35) else { return }
        warnings = WarningsEngine.compute(readings: readings, profile: profile)
    }
}

private struct WarningRow: View {
    let warning: HealthWarning

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: warning.type.icon)
                .font(.system(size: 22))
                .foregroundColor(warning.type.color)
                .frame(width: 44, height: 44)
                .background(warning.type.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text(warning.title)
                    .font(.system(size: 15, weight: .semibold))
                Text(warning.message)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                Text(warning.firedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if warning.resolvedAt != nil {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
}
