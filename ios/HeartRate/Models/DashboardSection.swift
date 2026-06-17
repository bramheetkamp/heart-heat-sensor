import Foundation

/// Identifiable sections that appear on the Dashboard.
/// The order and visibility of these sections can be customized by the user.
enum DashboardSection: String, CaseIterable, Codable, Identifiable {
    case aiSummary    = "aiSummary"
    case insights     = "insights"
    case streak       = "streak"
    case recovery     = "recovery"
    case weeklyTrend  = "weeklyTrend"
    case sleepQuality = "sleepQuality"
    case metrics      = "metrics"
    case warnings     = "warnings"
    case quickNav     = "quickNav"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .aiSummary:    return "AI Summary"
        case .insights:     return "Insights"
        case .streak:       return "Streak"
        case .recovery:     return "Recovery Score"
        case .weeklyTrend:  return "Weekly Trends"
        case .sleepQuality: return "Sleep Quality"
        case .metrics:      return "Metrics"
        case .warnings:     return "Active Alerts"
        case .quickNav:     return "Quick Navigation"
        }
    }

    var icon: String {
        switch self {
        case .aiSummary:    return "sparkles"
        case .insights:     return "lightbulb.fill"
        case .streak:       return "flame.fill"
        case .recovery:     return "bolt.heart.fill"
        case .weeklyTrend:  return "chart.line.uptrend.xyaxis"
        case .sleepQuality: return "moon.stars.fill"
        case .metrics:      return "grid.circle.fill"
        case .warnings:     return "exclamationmark.triangle.fill"
        case .quickNav:     return "arrow.right.circle.fill"
        }
    }
}

/// Persists dashboard section order and visibility to UserDefaults.
/// The companion/mascot status card is always pinned at the top and is not customizable.
@MainActor
final class DashboardLayoutService: ObservableObject {
    private let orderKey      = "dashboardSectionOrder"
    private let hiddenKey     = "dashboardHiddenSections"

    /// Ordered list of all sections (including hidden ones). Used by CustomizeDashboardView.
    @Published var sections: [DashboardSection]
    /// Set of section IDs the user has hidden.
    @Published var hiddenSections: Set<String>

    /// Sections that are currently visible, in user-defined order.
    var visibleSections: [DashboardSection] {
        sections.filter { !hiddenSections.contains($0.rawValue) }
    }

    init() {
        // Load persisted order
        if let raw = UserDefaults.standard.array(forKey: "dashboardSectionOrder") as? [String] {
            let known = Set(DashboardSection.allCases.map(\.rawValue))
            var ordered = raw.compactMap(DashboardSection.init(rawValue:)).filter { known.contains($0.rawValue) }
            // Append any new sections not yet in the saved order
            for s in DashboardSection.allCases where !ordered.contains(s) { ordered.append(s) }
            sections = ordered
        } else {
            sections = DashboardSection.allCases
        }

        // Load hidden set
        if let raw = UserDefaults.standard.array(forKey: "dashboardHiddenSections") as? [String] {
            hiddenSections = Set(raw)
        } else {
            hiddenSections = []
        }
    }

    func move(from source: IndexSet, to destination: Int) {
        sections.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    func toggleVisibility(of section: DashboardSection) {
        if hiddenSections.contains(section.rawValue) {
            hiddenSections.remove(section.rawValue)
        } else {
            hiddenSections.insert(section.rawValue)
        }
        persistHidden()
    }

    private func persist() {
        UserDefaults.standard.set(sections.map(\.rawValue), forKey: orderKey)
    }

    private func persistHidden() {
        UserDefaults.standard.set(Array(hiddenSections), forKey: hiddenKey)
    }
}
