import SwiftUI
import Charts

struct WarningDetailView: View {
    let warningId: UUID
    @EnvironmentObject private var env: AppEnvironment
    @State private var warning: HealthWarning?

    var body: some View {
        ScrollView {
            if let w = warning {
                VStack(spacing: 20) {
                    headerCard(w)
                    whyItFiredCard(w)
                    trendChartCard(w)
                    whatToDoCard(w)
                }
                .padding()
            } else {
                ProgressView("Loading…")
                    .padding(.top, 60)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Alert Detail")
        .navigationBarTitleDisplayMode(.inline)
        .task { loadWarning() }
    }

    // MARK: - Cards

    private func headerCard(_ w: HealthWarning) -> some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                Image(systemName: w.type.icon)
                    .font(.system(size: 32))
                    .foregroundColor(w.type.color)
                    .frame(width: 64, height: 64)
                    .background(w.type.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))

                VStack(alignment: .leading, spacing: 6) {
                    Text(w.title)
                        .font(.system(size: 20, weight: .bold))
                    Text(w.firedAt, style: .date)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            if let resolved = w.resolvedAt {
                Label("Resolved \(resolved.formatted(.relative(presentation: .named)))", systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundColor(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Label("Still active", systemImage: "exclamationmark.circle.fill")
                    .font(.footnote)
                    .foregroundColor(w.type.color)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
    }

    private func whyItFiredCard(_ w: HealthWarning) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Why this alert fired")
                .font(.system(size: 15, weight: .semibold))

            Text(w.context.explanation)
                .font(.system(size: 15))
                .foregroundColor(.secondary)
                .lineSpacing(4)

            Divider()

            VStack(spacing: 10) {
                ForEach(Array(w.context.triggerValues.keys.sorted()), id: \.self) { key in
                    if let trigger = w.context.triggerValues[key],
                       let baseline = w.context.baselineValues[key] {
                        ComparisonRow(
                            label: key,
                            current: trigger,
                            baseline: baseline,
                            color: w.type.color
                        )
                    }
                }
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
    }

    @ViewBuilder
    private func trendChartCard(_ w: HealthWarning) -> some View {
        if !w.context.trendValues.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Recent trend")
                    .font(.system(size: 15, weight: .semibold))

                Chart {
                    ForEach(Array(w.context.trendValues.enumerated()), id: \.offset) { i, v in
                        LineMark(
                            x: .value("Day", i),
                            y: .value("Value", v)
                        )
                        .foregroundStyle(w.type.color)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))

                        AreaMark(
                            x: .value("Day", i),
                            y: .value("Value", v)
                        )
                        .foregroundStyle(.linearGradient(
                            colors: [w.type.color.opacity(0.25), w.type.color.opacity(0.02)],
                            startPoint: .top, endPoint: .bottom
                        ))
                    }
                }
                .frame(height: 140)
                .chartXAxis(.hidden)
            }
            .padding()
            .background(.background, in: RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
        }
    }

    private func whatToDoCard(_ w: HealthWarning) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("What you can do", systemImage: "lightbulb.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.orange)

            ForEach(suggestionsFor(w.type), id: \.self) { suggestion in
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 6, height: 6)
                        .padding(.top, 6)
                    Text(suggestion)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .lineSpacing(3)
                }
            }

            Text("This is a wellness indicator based on your personal trends, not a medical diagnosis. If you have concerns, consult a healthcare professional.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 8)
                .lineSpacing(3)
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
    }

    // MARK: - Helpers

    private func loadWarning() {
        guard let profile = try? env.dataStore.getOrCreateProfile(),
              let readings = try? env.dataStore.recentReadings(days: 35) else { return }
        let all = WarningsEngine.compute(readings: readings, profile: profile)
        warning = all.first { $0.id == warningId }
    }

    private func suggestionsFor(_ type: HealthWarning.WarningType) -> [String] {
        switch type {
        case .overheating:
            return [
                "Move to a cooler environment and rest.",
                "Drink cool water — hydration helps regulate core temperature.",
                "If exercising, pause and allow your body to cool down.",
                "Monitor for other signs like dizziness or unusual fatigue."
            ]
        case .gettingSick:
            return [
                "Prioritize sleep — your body recovers best at night.",
                "Stay hydrated and consider lighter meals.",
                "Reduce intense exercise for a day or two.",
                "Watch the trend over the next 24–48 hours."
            ]
        case .fatigueRecovery:
            return [
                "Your heart rate variability suggests your body needs rest.",
                "Aim for an earlier bedtime tonight.",
                "Consider skipping intense workouts today.",
                "This often resolves after 1–2 nights of quality sleep."
            ]
        }
    }
}

// MARK: - Sub-components

private struct ComparisonRow: View {
    let label: String
    let current: Double
    let baseline: Double
    let color: Color

    private var delta: Double { current - baseline }
    private var pct: Double { baseline != 0 ? abs(delta / baseline) * 100 : 0 }

    var body: some View {
        HStack {
            Text(label.capitalized)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.1f", current))
                    .font(.system(size: 15, weight: .bold))
                HStack(spacing: 4) {
                    Image(systemName: delta >= 0 ? "arrow.up" : "arrow.down")
                        .font(.system(size: 10, weight: .bold))
                    Text(String(format: "%.1f%%", pct) + " vs baseline")
                        .font(.system(size: 11))
                }
                .foregroundColor(abs(delta) > 0.5 ? color : .secondary)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }
}
