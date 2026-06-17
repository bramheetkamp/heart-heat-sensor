import ActivityKit
import Foundation

/// ActivityAttributes shared between the HeartRate app target and the
/// PulseWidget extension. Defines the static attributes (set once) and the
/// dynamic ContentState (pushed on every BLE reading while a workout session
/// is active).
///
/// This file is compiled into BOTH targets — ActivityKit matches the request
/// (app) to the configuration (widget) by type name string, which resolves to
/// "HeartRateLiveActivityAttributes" regardless of which module compiled it.
struct HeartRateLiveActivityAttributes: ActivityAttributes {

    /// Dynamic — pushed to the live activity on every new BLE reading.
    public struct ContentState: Codable, Hashable {
        var heartRate: Int?
        var coreTemp: Double?
        /// Raw value of `HeatStrainEngine.Level`: 0 nominal / 1 elevated / 2 serious / 3 critical.
        var heatLevelRaw: Int
        var isWarning: Bool

        var hrDisplay: String { heartRate.map { "\($0)" } ?? "—" }
        var coreTempDisplay: String { coreTemp.map { String(format: "%.1f", $0) } ?? "—" }
    }

    /// Static — set once when the live activity is requested.
    var startDate: Date
    var characterName: String
}
