import Foundation

// MARK: - MascotCharacter

/// The visual companion character displayed throughout the app.
/// Characters are unlocked by accumulating days of recorded health data.
enum MascotCharacter: String, CaseIterable, Codable {
    case blob   // Default — the original round shape, always available
    case bear   // Always available — cozy and warm
    case owl    // Unlocked after 7 unique days of recorded data
    case fox    // Unlocked after 30 unique days of recorded data

    var displayName: String {
        switch self {
        case .blob: return "Blobby"
        case .bear: return "Bruno"
        case .owl:  return "Hoot"
        case .fox:  return "Ember"
        }
    }

    var emoji: String {
        switch self {
        case .blob: return "🫧"
        case .bear: return "🐻"
        case .owl:  return "🦉"
        case .fox:  return "🦊"
        }
    }

    var tagline: String {
        switch self {
        case .blob: return "Your original wellness buddy"
        case .bear: return "Cozy, warm, always there for you"
        case .owl:  return "The wise observer of your patterns"
        case .fox:  return "Quick to spot what you're missing"
        }
    }

    /// Minimum unique days of recorded data required to unlock. Zero = always unlocked.
    var unlockDays: Int {
        switch self {
        case .blob: return 0
        case .bear: return 0
        case .owl:  return 7
        case .fox:  return 30
        }
    }

    var unlockDescription: String {
        switch self {
        case .blob: return "Always available"
        case .bear: return "Always available"
        case .owl:  return "Record 7 days of health data to unlock"
        case .fox:  return "Record 30 days of health data to unlock"
        }
    }

    func isUnlocked(recordedDays: Int) -> Bool {
        recordedDays >= unlockDays
    }
}

// MARK: - AISummaryTone

/// The personality tone used by the on-device AI wellness summary.
enum AISummaryTone: String, CaseIterable, Codable {
    case encouraging  // Warm and supportive (default)
    case analytical   // Data-driven and precise
    case playful      // Light-hearted and fun
    case direct       // Brief and to the point

    var displayName: String {
        switch self {
        case .encouraging: return "Encouraging"
        case .analytical:  return "Analytical"
        case .playful:     return "Playful"
        case .direct:      return "Direct"
        }
    }

    var icon: String {
        switch self {
        case .encouraging: return "heart.fill"
        case .analytical:  return "chart.bar.fill"
        case .playful:     return "party.popper.fill"
        case .direct:      return "bolt.fill"
        }
    }

    var description: String {
        switch self {
        case .encouraging: return "Warm and supportive, highlights the positive"
        case .analytical:  return "Data-driven and precise, numbers-first"
        case .playful:     return "Light-hearted and easy, keeps it fun"
        case .direct:      return "Short and clear, no fluff"
        }
    }
}
