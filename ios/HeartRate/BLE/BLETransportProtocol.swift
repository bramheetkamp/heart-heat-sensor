import Foundation
import Combine

// MARK: - Measurement Types

struct HRMeasurement {
    let heartRate: Int          // bpm
    let rrIntervals: [Double]   // seconds
    let contactStatus: Bool?
}

struct TemperatureMeasurement {
    let value: Double           // Celsius
    let siteLabel: String       // "Skin" or "Core"
    let site: TemperatureSite
}

enum TemperatureSite: String, Codable {
    case skin = "Skin"
    case core = "Core"
    case unknown
}

// MARK: - Connection State

enum BLEConnectionState: Equatable {
    case disconnected
    case scanning
    case connecting
    case connected(peripheralName: String)
    case error(String)

    static func == (lhs: BLEConnectionState, rhs: BLEConnectionState) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected): return true
        case (.scanning, .scanning): return true
        case (.connecting, .connecting): return true
        case (.connected(let a), .connected(let b)): return a == b
        case (.error(let a), .error(let b)): return a == b
        default: return false
        }
    }

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var displayName: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .scanning: return "Scanning…"
        case .connecting: return "Connecting…"
        case .connected(let name): return name
        case .error(let msg): return "Error: \(msg)"
        }
    }
}

// MARK: - Transport Protocol

protocol BLETransportProtocol: AnyObject {
    var connectionStatePublisher: AnyPublisher<BLEConnectionState, Never> { get }
    var hrMeasurementPublisher: AnyPublisher<HRMeasurement, Never> { get }
    var temperaturePublisher: AnyPublisher<TemperatureMeasurement, Never> { get }
    func startScanning()
    func stopScanning()
    func disconnect()
}
