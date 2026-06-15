import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// On-device, privacy-preserving wellness summariser.
///
/// Turns the data the app *already* computes (latest readings + warning-engine
/// baselines + active warnings) into a short, friendly natural-language summary
/// using **Apple's Foundation Models** framework — the on-device LLM behind
/// Apple Intelligence. Nothing ever leaves the phone: this never touches
/// `SyncService` or the backend, and it works fully offline.
///
/// The whole feature is a *progressive enhancement*. It is only available on
/// devices that ship the on-device model (iOS 26+, Apple-Intelligence-capable
/// hardware, with the feature enabled). On every other device `availability`
/// reports `.unavailable` and the UI simply hides the summary — there is no
/// template fallback by design (see the Dashboard card).
@MainActor
final class HealthSummaryService: ObservableObject {

    /// Why the on-device summary can or cannot run right now.
    enum Availability: Equatable {
        case available
        /// Not usable on this device/state. `reason` is a short, user-facing line.
        case unavailable(reason: String)

        var isAvailable: Bool {
            if case .available = self { return true }
            return false
        }
    }

    /// Current availability of the on-device model. Re-evaluated each access so a
    /// user toggling Apple Intelligence in Settings is reflected without a relaunch.
    var availability: Availability {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(.deviceNotEligible):
                return .unavailable(reason: "This device doesn't support on-device AI summaries.")
            case .unavailable(.appleIntelligenceNotEnabled):
                return .unavailable(reason: "Turn on Apple Intelligence in Settings to get AI summaries.")
            case .unavailable(.modelNotReady):
                return .unavailable(reason: "The on-device model is still downloading. Try again shortly.")
            case .unavailable:
                return .unavailable(reason: "On-device AI summaries aren't available right now.")
            }
        } else {
            return .unavailable(reason: "On-device AI summaries need iOS 26 or later.")
        }
        #else
        return .unavailable(reason: "On-device AI summaries aren't available in this build.")
        #endif
    }

    var isAvailable: Bool { availability.isAvailable }

    // MARK: - Generation

    enum SummaryError: Error { case unavailable, generationFailed }

    /// Generate a short wellness summary entirely on-device.
    /// - Throws `SummaryError.unavailable` when the model can't run here.
    func summary(
        readings: [Reading],
        warnings: [HealthWarning],
        profile: UserProfile
    ) async throws -> String {
        let prompt = Self.buildPrompt(
            snapshot: Self.snapshot(readings: readings, warnings: warnings, profile: profile)
        )

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), case .available = availability {
            let session = LanguageModelSession(instructions: Self.instructions)
            do {
                let response = try await session.respond(
                    to: prompt,
                    options: GenerationOptions(temperature: 0.4)
                )
                let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { throw SummaryError.generationFailed }
                return text
            } catch is SummaryError {
                throw SummaryError.generationFailed
            } catch {
                throw SummaryError.generationFailed
            }
        }
        #endif

        throw SummaryError.unavailable
    }

    // MARK: - Prompt construction (pure & testable — no FoundationModels needed)

    /// System instructions: tight wellness framing, no medical/diagnostic language.
    nonisolated static let instructions = """
    You are a warm, encouraging wellness companion inside a consumer heart-rate \
    and body-temperature app. Given a snapshot of someone's recent biometrics, \
    write a short summary of how they seem to be doing.

    Rules:
    - 2 to 3 short sentences, plain and friendly. No lists, no headings, no emoji.
    - This is general wellness only. Never diagnose, never name illnesses or \
    medical conditions, and never give medical advice. Do not tell them to see a doctor.
    - If a metric is flagged as elevated or a warning is active, mention it gently \
    and suggest light self-care (rest, hydration, taking it easy).
    - If everything looks normal, reassure them and keep it upbeat.
    - Speak directly to the person as "you". Don't restate the raw numbers verbatim.
    """

    /// A compact, model-friendly numeric snapshot. Pure data so it can be unit-tested.
    struct Snapshot: Equatable {
        var latestHR: Int?
        var latestCoreTemp: Double?
        var latestSkinTemp: Double?
        var latestHRV: Double?
        var latestEDA: Double?
        var restingHR7d: Double?
        var restingHR30d: Double?
        var coreTemp7d: Double?
        var coreTemp30d: Double?
        var hrv7d: Double?
        var hrv30d: Double?
        var activeWarnings: [String]
    }

    /// Derive a `Snapshot` from raw inputs, reusing the warning engine's baselines.
    nonisolated static func snapshot(
        readings: [Reading],
        warnings: [HealthWarning],
        profile: UserProfile
    ) -> Snapshot {
        let latest = readings.max(by: { $0.timestamp < $1.timestamp })
        let resting = WarningsEngine.restingReadings(readings)
        return Snapshot(
            latestHR: latest?.heartRate,
            latestCoreTemp: latest?.tempCore,
            latestSkinTemp: latest?.tempSkin,
            latestHRV: latest?.rmssd,
            latestEDA: latest?.eda,
            restingHR7d: WarningsEngine.rollingAverage(readings: resting, days: 7, keyPath: \.heartRateForSummary),
            restingHR30d: WarningsEngine.rollingAverage(readings: resting, days: 30, keyPath: \.heartRateForSummary),
            coreTemp7d: WarningsEngine.rollingAverage(readings: resting, days: 7, keyPath: \.tempCore),
            coreTemp30d: WarningsEngine.rollingAverage(readings: resting, days: 30, keyPath: \.tempCore),
            hrv7d: WarningsEngine.rollingAverage(readings: resting, days: 7, keyPath: \.rmssd),
            hrv30d: WarningsEngine.rollingAverage(readings: resting, days: 30, keyPath: \.rmssd),
            activeWarnings: warnings.filter { $0.resolvedAt == nil }.map { "\($0.title): \($0.message)" }
        )
    }

    /// Render a snapshot into the user prompt fed to the on-device model.
    nonisolated static func buildPrompt(snapshot s: Snapshot) -> String {
        func fmt(_ v: Double?, _ format: String = "%.0f") -> String {
            guard let v else { return "no data" }
            return String(format: format, v)
        }
        func compare(_ recent: Double?, _ base: Double?, _ format: String = "%.0f") -> String {
            guard let recent, let base else { return fmt(recent, format) }
            let delta = recent - base
            let sign = delta >= 0 ? "+" : ""
            return "\(String(format: format, recent)) (7-day avg, baseline \(String(format: format, base)), \(sign)\(String(format: format, delta)) vs baseline)"
        }

        var lines: [String] = []
        lines.append("Here is the person's recent biometric snapshot.")
        lines.append("")
        lines.append("Latest reading:")
        lines.append("- Heart rate: \(s.latestHR.map { "\($0) bpm" } ?? "no data")")
        lines.append("- Core temperature: \(fmt(s.latestCoreTemp, "%.1f")) °C")
        lines.append("- Skin temperature: \(fmt(s.latestSkinTemp, "%.1f")) °C")
        lines.append("- HRV (RMSSD): \(fmt(s.latestHRV)) ms")
        if s.latestEDA != nil {
            lines.append("- Skin conductance (EDA): \(fmt(s.latestEDA, "%.1f")) µS")
        }
        lines.append("")
        lines.append("Trends (resting):")
        lines.append("- Resting heart rate: \(compare(s.restingHR7d, s.restingHR30d)) bpm")
        lines.append("- Resting core temperature: \(compare(s.coreTemp7d, s.coreTemp30d, "%.1f")) °C")
        lines.append("- HRV (RMSSD): \(compare(s.hrv7d, s.hrv30d)) ms")
        lines.append("")
        if s.activeWarnings.isEmpty {
            lines.append("Active wellness flags: none. Everything is within the person's normal range.")
        } else {
            lines.append("Active wellness flags:")
            for w in s.activeWarnings { lines.append("- \(w)") }
        }
        lines.append("")
        lines.append("Write the summary now.")
        return lines.joined(separator: "\n")
    }
}

// MARK: - Reading bridge for rollingAverage(keyPath:)

private extension Reading {
    /// `WarningsEngine.rollingAverage` takes `KeyPath<Reading, Double?>`; HR is an
    /// `Int?`, so expose a `Double?` view of it for baseline reuse.
    var heartRateForSummary: Double? { heartRate.map(Double.init) }
}
