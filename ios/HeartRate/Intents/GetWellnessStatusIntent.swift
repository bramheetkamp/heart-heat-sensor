import AppIntents
import Foundation

struct GetWellnessStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Wellness Status"
    static let description = IntentDescription(
        "Gives a quick wellness summary based on your latest Pulse readings."
    )
    static let openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let defaults = UserDefaults.standard
        let timestamp = defaults.double(forKey: "cachedReadingAt")
        guard timestamp > 0 else {
            return .result(dialog: "No data yet. Open Pulse and connect your sensor to start tracking.")
        }

        let hr       = defaults.object(forKey: "cachedHR") as? Int
        let coreTemp = defaults.double(forKey: "cachedCoreTemp")

        var concerns: [String] = []
        if let hr, hr > 100 {
            concerns.append("your heart rate is elevated at \(hr) BPM")
        }
        if coreTemp >= 38.5 {
            concerns.append("your core temperature is \(String(format: "%.1f", coreTemp))°C, above normal")
        }

        if concerns.isEmpty {
            let hrText = hr.map { "\($0) BPM" } ?? "not measured yet"
            return .result(dialog: "All looks good! Your heart rate is \(hrText) and temperature is normal.")
        } else {
            let concern = concerns.joined(separator: " and ")
            return .result(dialog: "Something to note: \(concern). Open Pulse for details.")
        }
    }
}
