import SwiftUI

struct ConnectionStatusBadge: View {
    let state: BLEConnectionState

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
                .overlay(
                    Circle()
                        .stroke(dotColor.opacity(0.3), lineWidth: 4)
                        .scaleEffect(isPulsing ? 1.8 : 1)
                        .opacity(isPulsing ? 0 : 1)
                        .animation(.easeOut(duration: 1.0).repeatForever(), value: isPulsing)
                )

            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(dotColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(dotColor.opacity(0.12), in: Capsule())
    }

    private var dotColor: Color {
        switch state {
        case .connected:    return .green
        case .connecting,
             .scanning:     return .orange
        case .disconnected: return .secondary
        case .error:        return .red
        }
    }

    private var label: String {
        switch state {
        case .connected(let name):  return name
        case .connecting:           return "Connecting…"
        case .scanning:             return "Scanning…"
        case .disconnected:         return "Disconnected"
        case .error(let msg):       return msg
        }
    }

    private var isPulsing: Bool {
        switch state {
        case .scanning, .connecting: return true
        default: return false
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        ConnectionStatusBadge(state: .connected(peripheralName: "nRF52840 DK"))
        ConnectionStatusBadge(state: .scanning)
        ConnectionStatusBadge(state: .connecting)
        ConnectionStatusBadge(state: .disconnected)
        ConnectionStatusBadge(state: .error("Permission denied"))
    }
    .padding()
}
