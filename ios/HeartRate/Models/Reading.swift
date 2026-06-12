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
        self.activity = activity
        self.deviceId = deviceId
        self.synced = synced
    }

    // MARK: - Activity Level

    enum ActivityLevel: String, Codable {
        case rest, active, sleep, unknown
    }

    // MARK: - Computed Properties

    /// Root Mean Square of Successive Differences (RMSSD) from RR intervals.
    /// Returns nil if fewer than 2 intervals are available.
    var rmssd: Double? {
        guard rrIntervals.count >= 2 else { return nil }
        var sumSquaredDiffs = 0.0
        for i in 1 ..< rrIntervals.count {
            let diff = rrIntervals[i] - rrIntervals[i - 1]
            sumSquaredDiffs += diff * diff
        }
        let mean = sumSquaredDiffs / Double(rrIntervals.count - 1)
        return sqrt(mean)
    }
}
