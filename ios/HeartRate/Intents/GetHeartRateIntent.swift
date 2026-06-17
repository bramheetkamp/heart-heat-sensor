import AppIntents
import Foundation

struct GetHeartRateIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Heart Rate"
    static let description = IntentDescription(
        "Returns your most recent heart rate reading from Pulse."
    )
    static let openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ReturnsValue<Int?> & ProvidesDialog {
        let defaults = UserDefaults.standard
        let timestamp = defaults.double(forKey: "cachedReadingAt")
        guard let hr = defaults.object(forKey: "cachedHR") as? Int, timestamp > 0 else {
            return .result(
                value: nil,
                dialog: "No heart rate data yet. Open Pulse and connect your sensor."
            )
        }

        let age = Int(-Date(timeIntervalSince1970: timestamp).timeIntervalSinceNow)
        if age < 90 {
            return .result(value: hr, dialog: "Your heart rate is \(hr) beats per minute.")
        } else {
            let mins = max(1, age / 60)
            return .result(
                value: hr,
                dialog: "Your last reading was \(hr) BPM, about \(mins) \(mins == 1 ? "minute" : "minutes") ago."
            )
        }
    }
}
