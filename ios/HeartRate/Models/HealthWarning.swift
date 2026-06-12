import Foundation
import SwiftUI

struct HealthWarning: Identifiable, Codable {
    let id: UUID
    let type: WarningType
    let firedAt: Date
    var resolvedAt: Date?
    let title: String
    let message: String
    let context: WarningContext
    let deepLinkPath: String   // e.g. "/warnings/<id>"

    var isResolved: Bool { resolvedAt != nil }

    // MARK: - Warning Type

    enum WarningType: String, Codable, CaseIterable {
        case overheating    = "OVERHEATING"
        case gettingSick    = "GETTING_SICK"
        case fatigueRecovery = "FATIGUE_RECOVERY"

        var color: Color {
            switch self {
            case .overheating:     return .red
            case .gettingSick:     return .orange
            case .fatigueRecovery: return .blue
            }
        }

        var icon: String {
            switch self {
            case .overheating:     return "thermometer.high"
            case .gettingSick:     return "cross.vial"
            case .fatigueRecovery: return "zzz"
            }
        }

        var displayName: String {
            switch self {
            case .overheating:     return "Overheating"
            case .gettingSick:     return "Getting Sick"
            case .fatigueRecovery: return "Fatigue / Poor Recovery"
            }
        }
    }

    // MARK: - Warning Context

    struct WarningContext: Codable {
        let triggerValues: [String: Double]
        let baselineValues: [String: Double]
        let trendValues: [Double]
        let explanation: String
    }
}
