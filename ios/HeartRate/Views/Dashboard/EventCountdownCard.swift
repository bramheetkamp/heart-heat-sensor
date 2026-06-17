import SwiftUI

// MARK: - EventCountdownCard

/// Dashboard card counting down to the user's target event (e.g. a race).
/// Tapping it (when no event is set) jumps to Settings to configure one.
struct EventCountdownCard: View {
    @EnvironmentObject private var env: AppEnvironment

    let eventName: String?
    let eventDate: Date?

    private var daysAway: Int? {
        guard let eventDate else { return nil }
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let target = cal.startOfDay(for: eventDate)
        return cal.dateComponents([.day], from: start, to: target).day
    }

    var body: some View {
        Group {
            if let name = eventName, !name.isEmpty, let days = daysAway {
                configured(name: name, days: days)
            } else {
                emptyState
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.quaternary, lineWidth: 1))
    }

    private func configured(name: String, days: Int) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(countLabel(days)).font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.orange)
                Text(subtitle(days)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Label("Target event", systemImage: "flag.checkered")
                    .font(.caption2).foregroundStyle(.secondary)
                Text(name).font(.headline).multilineTextAlignment(.trailing)
                if let eventDate {
                    Text(eventDate, format: .dateTime.day().month().year())
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var emptyState: some View {
        Button {
            env.router.navigate(to: .settings)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "flag.checkered.circle.fill")
                    .font(.title2).foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Set your race day").font(.headline).foregroundStyle(.primary)
                    Text("Count down to your event in Settings.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }

    private func countLabel(_ days: Int) -> String {
        switch days {
        case let d where d > 1:  return "\(d) days"
        case 1:                  return "Tomorrow"
        case 0:                  return "Today!"
        default:                 return "Done"
        }
    }

    private func subtitle(_ days: Int) -> String {
        switch days {
        case let d where d > 1:  return "until your event"
        case 1:                  return "your event is tomorrow"
        case 0:                  return "it's race day — good luck!"
        default:                 return "event has passed"
        }
    }
}
