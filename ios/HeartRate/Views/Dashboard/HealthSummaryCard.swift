import SwiftUI

/// On-device AI wellness summary, shown on the Dashboard.
///
/// This card is a *progressive enhancement*: it renders **nothing at all** on
/// devices without Apple's on-device model (see `HealthSummaryService`). On
/// capable devices it generates a short, friendly summary entirely on-device —
/// no network, nothing sent to the backend.
struct HealthSummaryCard: View {
    @EnvironmentObject private var env: AppEnvironment

    /// The readings the Dashboard already loaded — passed in so we don't run a
    /// second `@Query`.
    let readings: [Reading]
    /// The warnings the Dashboard already computed this refresh.
    let warnings: [HealthWarning]

    private enum LoadState: Equatable {
        case loading
        case loaded(String)
        case failed
    }

    @State private var state: LoadState = .loading

    /// Changes whenever the inputs that should drive a regeneration change:
    /// the active-warning set and the newest reading timestamp.
    private var regenerationKey: String {
        let activeIDs = warnings.filter { $0.resolvedAt == nil }.map(\.id.uuidString).sorted().joined()
        let latest = readings.max(by: { $0.timestamp < $1.timestamp })?.timestamp.timeIntervalSince1970 ?? 0
        return "\(activeIDs)|\(Int(latest))"
    }

    var body: some View {
        // Only present the card on devices that can actually run the model.
        if env.healthSummary.isAvailable {
            card
                .task(id: regenerationKey) { await generate() }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tint)
                Text("Your Summary")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                if case .loading = state {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        Task { await generate() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .accessibilityLabel("Regenerate summary")
                }
            }

            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(.tint.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
    }

    @ViewBuilder
    private var content: some View {
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
