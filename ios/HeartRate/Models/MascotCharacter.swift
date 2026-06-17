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

    /// A short, in-character status line for the given mascot state.
    /// Each character has a distinct voice: Blobby is warm, Bruno is nurturing,
    /// Hoot is analytical, Ember is sharp and direct.
    func statusMessage(for state: MascotState) -> String {
        switch (self, state) {
        // Blobby — friendly, simple, relatable
        case (.blob, .happy):    return "Everything looks good from where I'm sitting!"
        case (.blob, .sweating): return "Phew — you're running real warm right now."
        case (.blob, .worried):  return "Something feels a bit off. Take it easy today."
        case (.blob, .sleepy):   return "Your body's asking for rest. Listen to it."
        case (.blob, .cheering): return "You're on a roll — keep it up!"
        case (.blob, .scanning): return "Looking for your device…"
        case (.blob, .neutral):  return "Waiting for some readings…"

        // Bruno — cozy, nurturing, dad-energy
        case (.bear, .happy):    return "You're doing great today, buddy. Proud of you."
        case (.bear, .sweating): return "Hey — dial it back. You're getting too warm."
        case (.bear, .worried):  return "I'm keeping an eye on you. Go slow today."
        case (.bear, .sleepy):   return "Rest up, champ. Recovery is training too."
        case (.bear, .cheering): return "That's the spirit! You're absolutely crushing it."
        case (.bear, .scanning): return "Sniffing around for your device…"
        case (.bear, .neutral):  return "Just hanging out, waiting for data."

        // Hoot — wise, observational, slightly formal
        case (.owl, .happy):     return "Your metrics are within expected parameters. Well done."
        case (.owl, .sweating):  return "Elevated thermal signature detected. Hydrate immediately."
        case (.owl, .worried):   return "Resting readings have shifted from baseline. Monitor closely."
        case (.owl, .sleepy):    return "HRV suppression observed. Prioritise sleep tonight."
        case (.owl, .cheering):  return "Excellent consistency. The data speaks for itself."
        case (.owl, .scanning):  return "Scanning the environment for your device."
        case (.owl, .neutral):   return "Awaiting sufficient data to analyse."

        // Ember — sharp, quick, a hint of sass
        case (.fox, .happy):     return "Sharp today. Nothing's getting past you."
        case (.fox, .sweating):  return "Flagged it — temp's too high. Cool down, now."
        case (.fox, .worried):   return "Something's brewing. Your numbers say: slow down."
        case (.fox, .sleepy):    return "Recovery score is tanking. Rest. Seriously."
        case (.fox, .cheering):  return "On fire! (The good kind.) Keep this momentum."
        case (.fox, .scanning):  return "On the hunt for your device…"
        case (.fox, .neutral):   return "Nothing to report yet. Stand by."
        }
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
