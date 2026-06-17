import Foundation
import UserNotifications

// MARK: - NotificationService

/// Manages local notifications for health warnings, streak milestones, and
/// character unlocks. Requests authorization, de-duplicates warnings, fires
/// milestone banners when streak days cross thresholds, and schedules a
/// recurring Sunday morning weekly-digest reminder.
@MainActor
final class NotificationService: NSObject, ObservableObject {

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    /// Set by AppEnvironment so notification taps can deep-link into the app.
    weak var router: AppRouter?

    private let center = UNUserNotificationCenter.current()
    private let notifiedKey       = "notifiedWarningIDs"
    private let lastMilestoneKey  = "lastNotifiedStreakMilestone"
    private let milestones        = [7, 14, 30, 60, 90, 180]

    override init() {
        super.init()
        center.delegate = self
    }

    // MARK: - Authorization

    /// Ask the user for permission to send notifications (no-op if already decided).
    /// On first grant, schedules the weekly digest automatically.
    func requestAuthorization() async {
        await refreshStatus()
        guard authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        await refreshStatus()
        if authorizationStatus == .authorized || authorizationStatus == .provisional {
            await scheduleWeeklyDigest()
        }
    }

    func refreshStatus() async {
        authorizationStatus = await center.notificationSettings().authorizationStatus
    }

    // MARK: - Health Warning Notifications

    /// Post notifications for any active warnings not already announced, and
    /// forget warnings that are no longer active so they can re-fire later.
    func notifyIfNeeded(for warnings: [HealthWarning]) async {
        await refreshStatus()
        guard authorizationStatus == .authorized || authorizationStatus == .provisional else { return }

        let active = warnings.filter { $0.resolvedAt == nil }
        let activeIDs = Set(active.map { $0.id.uuidString })
        var notified = Set(UserDefaults.standard.stringArray(forKey: notifiedKey) ?? [])

        for warning in active where !notified.contains(warning.id.uuidString) {
            let content = UNMutableNotificationContent()
            content.title = warning.title
            content.body = warning.message
            content.sound = .default
            content.userInfo = ["warningId": warning.id.uuidString]

            // Deliver immediately (nil trigger).
            let request = UNNotificationRequest(
                identifier: warning.id.uuidString,
                content: content,
                trigger: nil
            )
            try? await center.add(request)
            notified.insert(warning.id.uuidString)
        }

        // Drop ids that are no longer active so a recurrence re-notifies.
        notified.formIntersection(activeIDs)
        UserDefaults.standard.set(Array(notified), forKey: notifiedKey)
    }

    // MARK: - Live Heat-Strain Alerts

    /// Throttle state for the live heat alert (per-session, in-memory).
    private var lastHeatAlertLevel: Int = -1

    /// Fire an active, interruptive alert while a workout is overheating.
    /// Unlike `notifyIfNeeded`, this is for the LIVE session: it is intentionally
    /// loud and only (re)fires when the level rises to a new, higher severity, so
    /// an escalation (serious → critical) always cuts through but the same level
    /// doesn't spam.
    func notifyHeatStrain(level: HeatStrainEngine.Level, message: String) async {
        guard level.shouldAlert else { lastHeatAlertLevel = level.rawValue; return }
        guard level.rawValue > lastHeatAlertLevel else { return }
        lastHeatAlertLevel = level.rawValue

        await refreshStatus()
        guard authorizationStatus == .authorized || authorizationStatus == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = level == .critical ? "🛑 Stop now — overheating" : "⚠️ Slow down — overheating"
        content.body = message
        content.userInfo = ["type": "heatStrain"]
        content.interruptionLevel = level == .critical ? .critical : .timeSensitive
        content.sound = level == .critical ? .defaultCritical : .default

        let request = UNNotificationRequest(
            identifier: "heat_strain_\(level.rawValue)",
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }

    /// Reset the heat-alert throttle when a workout starts/ends so a later
    /// session re-alerts from scratch.
    func resetHeatStrainAlerts() { lastHeatAlertLevel = -1 }

    // MARK: - Streak Milestone Notifications

    /// Fires a local notification when the streak crosses a new milestone.
    /// Character-unlock milestones (7 and 30 days) get special unlock messages;
    /// other milestones get character-voiced encouragement.
    func checkAndNotifyStreak(days: Int, character: MascotCharacter) async {
        guard days > 0 else { return }
        await refreshStatus()
        guard authorizationStatus == .authorized || authorizationStatus == .provisional else { return }

        let lastNotified = UserDefaults.standard.integer(forKey: lastMilestoneKey)
        guard let milestone = milestones.first(where: { $0 > lastNotified && days >= $0 }) else { return }

        let content = UNMutableNotificationContent()
        content.sound = .default
        content.userInfo = ["type": "streak", "milestone": milestone]

        switch milestone {
        case 7:
            content.title = "🦉 Hoot is unlocked!"
            content.body = "7 days of health tracking — Hoot the Owl has joined your companion gallery. Tap Settings to switch."
        case 30:
            content.title = "🦊 Ember is unlocked!"
            content.body = "30 days strong! Ember the Fox is now available in your companion gallery."
        default:
            content.title = "\(milestone)-day streak!"
            content.body = streakBody(for: milestone, character: character)
        }

        let request = UNNotificationRequest(
            identifier: "streak_milestone_\(milestone)",
            content: content,
            trigger: nil
        )
        try? await center.add(request)
        UserDefaults.standard.set(milestone, forKey: lastMilestoneKey)
    }

    private func streakBody(for milestone: Int, character: MascotCharacter) -> String {
        switch character {
        case .blob:  return "\(milestone) days in a row — you're absolutely on a roll!"
        case .bear:  return "\(milestone) days straight. Proud of you, champ."
        case .owl:   return "\(milestone) consecutive days of health data. Statistically impressive."
        case .fox:   return "\(milestone) days. You're clearly not messing around."
        }
    }

    // MARK: - Morning Readiness Briefing

    /// Schedules (or replaces) a daily 8 AM notification containing the user's
    /// current recovery score voiced by their active companion character.
    /// No-op if the user has turned off morning briefings (`morningBriefingEnabled`
    /// UserDefaults key) or notifications are not authorized.
    func scheduleMorningBriefing(score: Int?, character: MascotCharacter) async {
        guard UserDefaults.standard.bool(forKey: "morningBriefingEnabled") else {
            center.removePendingNotificationRequests(withIdentifiers: ["morning_briefing"])
            return
        }
        await refreshStatus()
        guard authorizationStatus == .authorized || authorizationStatus == .provisional else { return }

        center.removePendingNotificationRequests(withIdentifiers: ["morning_briefing"])

        let content = UNMutableNotificationContent()
        content.sound = .default
        content.userInfo = ["type": "morningBriefing"]

        if let score {
            let label = score >= 82 ? "Excellent" : score >= 65 ? "Good" : score >= 45 ? "Fair" : "Low"
            content.title = "Morning check-in — Recovery \(score) (\(label))"
            content.body  = morningBody(score: score, character: character)
        } else {
            content.title = "Good morning from \(character.displayName)!"
            content.body  = character.statusMessage(for: .happy)
        }

        var components = DateComponents()
        components.hour   = 8
        components.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: "morning_briefing", content: content, trigger: trigger)
        try? await center.add(request)
    }

    private func morningBody(score: Int, character: MascotCharacter) -> String {
        switch character {
        case .blob:
            if score >= 82 { return "You're fully charged — ready to take on anything today!" }
            if score >= 65 { return "Feeling pretty solid. A good day ahead." }
            return "Take it easy today and let your body catch up."
        case .bear:
            if score >= 82 { return "Ready to roll. All systems go, champ." }
            if score >= 65 { return "Good enough to get after it. Pace yourself." }
            return "Rest up today. Your body's working hard behind the scenes."
        case .owl:
            if score >= 82 { return "Peak biometric indicators. Optimal performance window detected." }
            if score >= 65 { return "Metrics within acceptable range. Moderate exertion is advisable." }
            return "Recovery deficit detected. Prioritise sleep and low-intensity activity."
        case .fox:
            if score >= 82 { return "You're on fire right now — make the most of it." }
            if score >= 65 { return "Solid day ahead. Keep that momentum going." }
            return "Smart move to take it slow today. Know your limits, then exceed them tomorrow."
        }
    }

    // MARK: - Weekly Digest

    /// Schedules (or re-schedules) a recurring Sunday 9 AM reminder to review
    /// the weekly health summary. Safe to call multiple times — always replaces
    /// any existing scheduled request with the same identifier.
    func scheduleWeeklyDigest() async {
        await refreshStatus()
        guard authorizationStatus == .authorized || authorizationStatus == .provisional else { return }

        center.removePendingNotificationRequests(withIdentifiers: ["weekly_digest"])

        let content = UNMutableNotificationContent()
        content.title = "Your weekly health summary"
        content.body = "Open Pulse to see how your heart rate, temperature, and HRV trended this week."
        content.sound = .default
        content.userInfo = ["type": "weeklyDigest"]

        var components = DateComponents()
        components.weekday = 1  // Sunday
        components.hour = 9
        components.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: "weekly_digest", content: content, trigger: trigger)
        try? await center.add(request)
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationService: UNUserNotificationCenterDelegate {

    /// Show banners even while the app is in the foreground.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// Route a tapped notification to the matching screen.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let idString = userInfo["warningId"] as? String,
           let url = URL(string: "heartrate://warnings/\(idString)") {
            Task { @MainActor in self.router?.handle(url: url) }
        } else if let type = userInfo["type"] as? String {
            Task { @MainActor in
                switch type {
                case "streak":
                    // Character unlock milestones go to settings; others stay on dashboard
                    let milestone = userInfo["milestone"] as? Int ?? 0
                    if milestone == 7 || milestone == 30 {
                        self.router?.handle(url: URL(string: "heartrate://settings")!)
                    }
                case "weeklyDigest", "morningBriefing":
                    self.router?.handle(url: URL(string: "heartrate://dashboard")!)
                case "heatStrain":
                    self.router?.handle(url: URL(string: "heartrate://workout")!)
                default: break
                }
            }
        }
        completionHandler()
    }
}
