import SwiftUI

/// Daily-streak dashboard card: a flame, the current run, and a ring tracking
/// progress toward the next companion-unlock milestone. The streak count is
/// computed by `DashboardView` (it also drives streak notifications) and passed
/// in, so this view stays a pure function of `streakDays`.
struct StreakCard: View {
    let streakDays: Int

    var body: some View {
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
                milestoneRing
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }

    private var milestoneRing: some View {
        let milestone = Self.nextMilestone(from: streakDays)
        let base = Self.previousMilestone(from: streakDays)
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

    // MARK: - Milestone math

    static func nextMilestone(from days: Int) -> Int {
        [7, 14, 30, 60, 90, 180].first { $0 > days } ?? 180
    }

    static func previousMilestone(from days: Int) -> Int {
        ([0, 7, 14, 30, 60, 90] as [Int]).last { $0 <= days } ?? 0
    }

    private func streakSubtitle(for days: Int) -> String {
        let next = Self.nextMilestone(from: days)
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
}
