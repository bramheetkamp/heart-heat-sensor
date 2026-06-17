import SwiftUI

/// Dashboard card showing up to 3 ranked, rule-based health insights generated
/// by `InsightsEngine`. Always available — no AI model required. Complements the
/// `HealthSummaryCard` (which only appears on iOS 26+ Apple Intelligence devices).
struct InsightsCard: View {
    let readings: [Reading]
    let warnings: [HealthWarning]

    private var insights: [Insight] {
        InsightsEngine.generate(readings: readings, warnings: warnings, maxCount: 3)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Insights", systemImage: "lightbulb.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.yellow)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(insights) { insight in
                    insightRow(insight)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
    }

    private func insightRow(_ insight: Insight) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: insight.systemImage)
                .font(.system(size: 14))
                .foregroundStyle(levelColor(insight.level))
                .frame(width: 20, alignment: .center)
                .padding(.top, 1)
            Text(insight.text)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
        }
    }

    private func levelColor(_ level: Insight.Level) -> Color {
        switch level {
        case .good:    return .green
        case .caution: return .orange
        case .alert:   return .red
        case .neutral: return .secondary
        }
    }
}
