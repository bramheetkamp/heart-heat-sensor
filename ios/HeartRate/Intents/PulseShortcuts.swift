import AppIntents

struct PulseShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetHeartRateIntent(),
            phrases: [
                "What's my heart rate in \(.applicationName)",
                "Check my heart rate in \(.applicationName)",
                "Show my heart rate with \(.applicationName)",
                "Read heart rate from \(.applicationName)"
            ],
            shortTitle: "Heart Rate",
            systemImageName: "heart.fill"
        )
        AppShortcut(
            intent: GetWellnessStatusIntent(),
            phrases: [
                "How am I doing in \(.applicationName)",
                "Check my wellness in \(.applicationName)",
                "What's my health status in \(.applicationName)",
                "Am I healthy in \(.applicationName)"
            ],
            shortTitle: "Wellness Status",
            systemImageName: "waveform.path.ecg.rectangle"
        )
    }
}
