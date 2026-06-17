import SwiftUI

// Reusable building blocks for the dashboard. Kept separate from `DashboardView`
// so the screen file stays focused on layout/state and these stay easy to reuse.

// MARK: - Metric Card

struct MetricCard<Content: View>: View {
    let title: String
    let icon: String
    let iconColor: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(iconColor)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
            }
            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }
}

// MARK: - Warning Row Card

struct WarningRowCard: View {
    let warning: HealthWarning

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: warning.type.icon)
                .font(.system(size: 20))
                .foregroundColor(warning.type.color)
                .frame(width: 36, height: 36)
                .background(warning.type.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(warning.title)
                    .font(.system(size: 15, weight: .semibold))
                Text(warning.message)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(warning.type.color.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Quick Nav Button

struct QuickNavButton: View {
    let icon: String
    let label: String
    var badge: Int = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: icon)
                        .font(.system(size: 22))
                        .foregroundColor(.orange)
                        .frame(width: 44, height: 44)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

                    if badge > 0 {
                        Text("\(badge)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(3)
                            .background(Color.red, in: Circle())
                            .offset(x: 6, y: -6)
                    }
                }
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(.background, in: RoundedRectangle(cornerRadius: 16))
        }
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
    }
}
