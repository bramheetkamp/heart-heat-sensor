import Foundation
import UserNotifications

// MARK: - NotificationService

/// Manages local notifications for health warnings: requests authorization,
/// posts a notification when a new warning becomes active (de-duplicated so the
/// same warning isn't re-announced on every refresh), and routes a tapped
/// notification to the relevant warning detail via the app router.
@MainActor
final class NotificationService: NSObject, ObservableObject {

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    /// Set by AppEnvironment so notification taps can deep-link into the app.
    weak var router: AppRouter?

    private let center = UNUserNotificationCenter.current()
    private let notifiedKey = "notifiedWarningIDs"

    override init() {
        super.init()
        center.delegate = self
    }

    // MARK: - Authorization

    /// Ask the user for permission to send notifications (no-op if already decided).
    func requestAuthorization() async {
        await refreshStatus()
        guard authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        await refreshStatus()
    }

    func refreshStatus() async {
        authorizationStatus = await center.notificationSettings().authorizationStatus
    }

    // MARK: - Firing

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

    /// Route a tapped notification to the matching warning detail.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let idString = userInfo["warningId"] as? String,
           let url = URL(string: "heartrate://warnings/\(idString)") {
            Task { @MainActor in self.router?.handle(url: url) }
        }
        completionHandler()
    }
}
