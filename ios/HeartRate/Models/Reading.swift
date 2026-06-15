import Foundation
import SwiftData

@Model
final class Reading {
    var id: UUID
    var timestamp: Date
    var heartRate: Int?          // bpm
    var rrIntervals: [Double]    // seconds
    var tempCore: Double?        // Celsius, core site
    var tempSkin: Double?        // Celsius, skin site
    var eda: Double?             // skin conductance, microsiemens (µS) — BodyTempSensor only
    var activity: ActivityLevel
    var deviceId: String
    var synced: Bool

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        heartRate: Int? = nil,
        rrIntervals: [Double] = [],
        tempCore: Double? = nil,
        tempSkin: Double? = nil,
        eda: Double? = nil,
        activity: ActivityLevel = .unknown,
        deviceId: String = "",
        synced: Bool = false
    ) {
        self.id = id
        self.timestamp = timestamp
        self.heartRate = heartRate
        self.rrIntervals = rrIntervals
        self.tempCore = tempCore
        self.tempSkin = tempSkin
        self.eda = eda
        self.activity = activity
        self.deviceId = deviceId
        self.synced = synced
    }

    // MARK: - Activity Level

    enum ActivityLevel: String, Codable {
        case rest, active, sleep, unknown
    }

    // MARK: - Computed Properties

    /// Root Mean Square of Successive Differences (RMSSD) from RR intervals,
    /// expressed in milliseconds (the standard HRV unit, as displayed in the UI).
    /// Returns nil if fewer than 2 intervals are available.
    var rmssd: Double? {
        guard rrIntervals.count >= 2 else { return nil }
        var sumSquaredDiffs = 0.0
        for i in 1 ..< rrIntervals.count {
            let diff = rrIntervals[i] - rrIntervals[i - 1]
            sumSquaredDiffs += diff * diff
        }
        let mean = sumSquaredDiffs / Double(rrIntervals.count - 1)
        // RR intervals are stored in seconds; convert RMSSD to milliseconds.
        return sqrt(mean) * 1000.0
    }
}
