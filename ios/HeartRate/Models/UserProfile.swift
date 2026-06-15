import Foundation
import SwiftData

@Model
final class UserProfile {
    var id: UUID
    var displayName: String
    var email: String?
    var createdAt: Date

    // Warning thresholds
    var overheatingThreshold: Double    // default 38.5 °C
    var sickHRThreshold: Double         // default 5.0 bpm above baseline
    var sickTempThreshold: Double       // default 0.3 °C above baseline
    var fatigueHRThreshold: Double      // default 8% above baseline resting HR
    var fatigueHRVThreshold: Double     // default 80% of baseline HRV (RMSSD)

    // Backend sync credentials
    var backendToken: String?
    var backendUserId: String?

    init(
        id: UUID = UUID(),
        displayName: String = "User",
        email: String? = nil,
        createdAt: Date = Date(),
        overheatingThreshold: Double = 38.5,
        sickHRThreshold: Double = 5.0,
        sickTempThreshold: Double = 0.3,
        fatigueHRThreshold: Double = 0.08,
        fatigueHRVThreshold: Double = 0.80,
        backendToken: String? = nil,
        backendUserId: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.email = email
        self.createdAt = createdAt
        self.overheatingThreshold = overheatingThreshold
        self.sickHRThreshold = sickHRThreshold
        self.sickTempThreshold = sickTempThreshold
        self.fatigueHRThreshold = fatigueHRThreshold
        self.fatigueHRVThreshold = fatigueHRVThreshold
        self.backendToken = backendToken
        self.backendUserId = backendUserId
    }
}
