import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Helpers

private func heatColor(for rawLevel: Int) -> Color {
    switch rawLevel {
    case 3: return .red
    case 2: return .orange
    case 1: return Color(red: 0.95, green: 0.7, blue: 0.15) // amber
    default: return .green
    }
}

// MARK: - Lock Screen / StandBy View

/// Compact banner shown on the Lock Screen and in StandBy mode while a session is active.
struct PulseLiveActivityLockScreenView: View {
    let state: HeartRateLiveActivityAttributes.ContentState
    let startDate: Date
    let characterName: String

    var body: some View {
        HStack(spacing: 0) {
            metricColumn(
                icon: "heart.fill",
                iconColor: .red,
                value: state.hrDisplay,
                unit: "bpm"
            )
            Divider()
                .frame(height: 52)
                .padding(.horizontal, 10)

            metricColumn(
                icon: "thermometer.medium",
                iconColor: heatColor(for: state.heatLevelRaw),
                value: state.coreTempDisplay,
                unit: "°C core"
            )
            Divider()
                .frame(height: 52)
                .padding(.horizontal, 10)

            // Elapsed timer (auto-updates every second — no custom timer needed)
            VStack(spacing: 3) {
                Image(systemName: "stopwatch")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.orange)
                Text(startDate, style: .timer)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.orange)
                    .monospacedDigit()
                    .frame(minWidth: 56)
                Text("elapsed")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .overlay(alignment: .topLeading) {
            HStack(spacing: 4) {
                Image(systemName: "bolt.heart.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.purple)
                Text("PULSE LIVE")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 6)
            .padding(.leading, 20)
        }
    }

    private func metricColumn(icon: String, iconColor: Color, value: String, unit: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(iconColor)
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(iconColor)
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(unit)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Live Activity Widget

struct PulseLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: HeartRateLiveActivityAttributes.self) { context in
            // Lock Screen / StandBy
            PulseLiveActivityLockScreenView(
                state: context.state,
                startDate: context.attributes.startDate,
                characterName: context.attributes.characterName
            )
            .activityBackgroundTint(Color(.systemBackground).opacity(0.95))
            .activitySystemActionForegroundColor(.primary)
            .widgetURL(URL(string: "heartrate://workout"))

        } dynamicIsland: { context in
            DynamicIsland {
                // MARK: Expanded (long-press on island)
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.red)
                            Text("HR")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        Text(context.state.hrDisplay)
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(.red)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text("bpm")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, 6)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 4) {
                            Text("CORE")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Image(systemName: "thermometer.medium")
                                .font(.system(size: 11))
                                .foregroundStyle(heatColor(for: context.state.heatLevelRaw))
                        }
                        Text(context.state.coreTempDisplay)
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(heatColor(for: context.state.heatLevelRaw))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text("°C")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.trailing, 6)
                }

                DynamicIslandExpandedRegion(.center) {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.heart.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.purple)
                        Text(context.attributes.characterName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Label("Session", systemImage: "stopwatch")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(context.attributes.startDate, style: .timer)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.orange)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                }

            } compactLeading: {
                // Compact leading: live HR
                HStack(spacing: 3) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                    Text(context.state.hrDisplay)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }

            } compactTrailing: {
                // Compact trailing: core temp with heat-level tint
                HStack(spacing: 2) {
                    Image(systemName: "thermometer.medium")
                        .font(.system(size: 9))
                        .foregroundStyle(heatColor(for: context.state.heatLevelRaw))
                    Text(context.state.coreTempDisplay + "°")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(heatColor(for: context.state.heatLevelRaw))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }

            } minimal: {
                // Minimal: HR only (two-app shared island)
                Text(context.state.hrDisplay)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.red)
                    .monospacedDigit()
            }
            .keylineTint(heatColor(for: context.state.heatLevelRaw))
            .widgetURL(URL(string: "heartrate://workout"))
        }
    }
}
