import SwiftUI

/// Wellness summary card shown on the Dashboard.
///
/// On devices with Apple Intelligence (iOS 26+, model downloaded): generates
/// a 2-3 sentence natural-language summary on-device via Foundation Models.
///
/// On all other devices: shows up to 3 rule-based insights from InsightsEngine
/// so every user gets personalised, data-driven feedback regardless of OS.
struct HealthSummaryCard: View {
    @EnvironmentObject private var env: AppEnvironment

    let readings: [Reading]
    let warnings: [HealthWarning]

    private enum LoadState: Equatable {
        case loading
        case loaded(String)
        case failed
    }

    @State private var state: LoadState = .loading

    private var regenerationKey: String {
        let activeIDs = warnings.filter { $0.resolvedAt == nil }.map(\.id.uuidString).sorted().joined()
        let latest = readings.max(by: { $0.timestamp < $1.timestamp })?.timestamp.timeIntervalSince1970 ?? 0
        return "\(activeIDs)|\(Int(latest))"
    }

    var body: some View {
        if env.healthSummary.isAvailable {
            aiCard
                .task(id: regenerationKey) { await generate() }
        } else {
            insightsCard
        }
    }

    // MARK: - AI Card (iOS 26+ / Apple Intelligence)

    private var aiCard: some View {
        cardShell(title: "Your Summary", icon: "sparkles", tinted: true) {
            aiContent
        } refreshAction: {
            Task { await generate() }
        } isLoading: {
            state == .loading
        }
    }

    @ViewBuilder
    private var aiContent: some View {
        switch state {
        case .loading:
            Text("Reading your latest signals…")
                .font(.footnote)
                .foregroundColor(.secondary)
                .redacted(reason: .placeholder)
        case .loaded(let text):
            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Generated privately on your device")
                .font(.caption2)
                .foregroundColor(.secondary)
        case .failed:
            Text("Couldn't generate a summary just now. Tap to try again.")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Rule-Based Insights Card (all devices)

    private var insightsCard: some View {
        let insights = InsightsEngine.generate(readings: readings, warnings: warnings)
        return cardShell(title: "Insights", icon: "chart.line.uptrend.xyaxis", tinted: false) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(insights) { insight in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: insight.systemImage)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(insight.level.color)
                            .frame(width: 20)
                        Text(insight.text)
                            .font(.system(size: 13))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        } refreshAction: nil isLoading: { false }
    }

    // MARK: - Shared shell

    private func cardShell<Content: View>(
        title: String,
        icon: String,
        tinted: Bool,
        @ViewBuilder content: () -> Content,
        refreshAction: (() -> Void)?,
        isLoading: () -> Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tinted ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.orange))
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                if isLoading() {
                    ProgressView().controlSize(.small)
                } else if let action = refreshAction {
                    Button(action: action) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .accessibilityLabel("Regenerate summary")
                }
            }
            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(tinted ? AnyShapeStyle(.tint.opacity(0.18)) : AnyShapeStyle(Color.orange.opacity(0.12)), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
    }

    // MARK: - AI generation

    @MainActor
    private func generate() async {
        state = .loading
        do {
            let profile = (try? env.dataStore.getOrCreateProfile()) ?? UserProfile()
            let text = try await env.healthSummary.summary(
                readings: readings,
                warnings: warnings,
                profile: profile
            )
            state = .loaded(text)
        } catch {
            state = .failed
        }
    }
}

// MARK: - Insight.Level → Color

private extension Insight.Level {
    var color: Color {
        switch self {
        case .good:    return .green
        case .caution: return .orange
        case .alert:   return .red
        case .neutral: return .secondary
        }
    }
}
