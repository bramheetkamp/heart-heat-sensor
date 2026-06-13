import Foundation

enum AppRoute: Hashable {
    case dashboard
    case history(metric: HistoryMetric)
    case warningDetail(id: UUID)
    case settings
    case pair

    // MARK: - History Metric

    enum HistoryMetric: String, Hashable {
        case heartRate = "hr"
        case coreTemp  = "core"
        case skinTemp  = "skin"
        case hrv       = "hrv"
    }

    // MARK: - URL Parsing

    /// Parse a deep link or universal link URL into an AppRoute.
    ///
    /// Supported schemes:
    ///   heartrate://dashboard
    ///   heartrate://history/hr  (or core, skin, hrv)
    ///   heartrate://warnings/<uuid>
    ///   heartrate://settings
    ///   heartrate://pair
    ///
    /// Universal links use the same path structure under any https:// host.
    static func from(url: URL) -> AppRoute? {
        // Normalize: extract host + path components depending on scheme
        let components: URLComponents?
        if url.scheme == "heartrate" {
            // heartrate://dashboard → host="dashboard", path=""
            // heartrate://history/hr → host="history", path="/hr"
            components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        } else if url.scheme == "https" || url.scheme == "http" {
            components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        } else {
            return nil
        }

        guard let comps = components else { return nil }

        // Build a path string we can match against regardless of scheme
        // For heartrate:// — host is the first path segment
        // For https://    — path starts with "/"
        var pathSegments: [String]

        if url.scheme == "heartrate" {
            let host = comps.host ?? ""
            let rest = comps.path
                .split(separator: "/", omittingEmptySubsequences: true)
                .map(String.init)
            pathSegments = [host] + rest
        } else {
            pathSegments = comps.path
                .split(separator: "/", omittingEmptySubsequences: true)
                .map(String.init)
        }

        guard let first = pathSegments.first else { return nil }

        switch first {
        case "dashboard":
            return .dashboard

        case "history":
            let metricRaw = pathSegments.count > 1 ? pathSegments[1] : "hr"
            let metric = HistoryMetric(rawValue: metricRaw) ?? .heartRate
            return .history(metric: metric)

        case "warnings":
            guard pathSegments.count > 1,
                  let uuid = UUID(uuidString: pathSegments[1]) else {
                return nil
            }
            return .warningDetail(id: uuid)

        case "settings":
            return .settings

        case "pair":
            return .pair

        default:
            return nil
        }
    }
}
