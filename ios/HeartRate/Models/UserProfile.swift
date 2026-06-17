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

    // Companion character and AI tone — stored as optional Strings so that
    // existing SwiftData rows (nil) migrate cleanly; computed properties
    // return the default when nil.
    var selectedCharacterRaw: String?
    var aiToneRaw: String?

    // Target event (e.g. a race) for the dashboard countdown. Optional so
    // existing SwiftData rows migrate cleanly.
    var eventName: String?
    var eventDate: Date?

    // Backend sync credentials
    var backendToken: String?
    var backendUserId: String?

    // MARK: - Typed accessors

    var selectedCharacter: MascotCharacter {
        get { MascotCharacter(rawValue: selectedCharacterRaw ?? "") ?? .blob }
        set { selectedCharacterRaw = newValue.rawValue }
    }

    var aiTone: AISummaryTone {
        get { AISummaryTone(rawValue: aiToneRaw ?? "") ?? .encouraging }
        set { aiToneRaw = newValue.rawValue }
    }

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
        selectedCharacter: MascotCharacter = .blob,
        aiTone: AISummaryTone = .encouraging,
        eventName: String? = nil,
        eventDate: Date? = nil,
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
        self.selectedCharacterRaw = selectedCharacter.rawValue
        self.aiToneRaw = aiTone.rawValue
        self.eventName = eventName
        self.eventDate = eventDate
        self.backendToken = backendToken
        self.backendUserId = backendUserId
    }
}
