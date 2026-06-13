import Foundation

// MARK: - Parse Errors

enum ParseError: Error, LocalizedError {
    case tooShort
    case invalidFormat(String)

    var errorDescription: String? {
        switch self {
        case .tooShort:
            return "Data is too short to parse."
        case .invalidFormat(let reason):
            return "Invalid format: \(reason)"
        }
    }
}

// MARK: - HR Measurement Parser

/// Parses Bluetooth Heart Rate Measurement characteristic (0x2A37) per the Bluetooth SIG spec.
enum HRMeasurementParser {

    /// Parse raw characteristic data into an HRMeasurement.
    ///
    /// Byte 0 — Flags:
    ///   bit 0:   Heart Rate Value Format (0 = uint8, 1 = uint16)
    ///   bits 1-2: Sensor Contact Status
    ///   bit 4:   Energy Expended Present
    ///   bit 5:   RR-Interval Present
    ///
    /// Following the flags byte:
    ///   1 or 2 bytes — Heart Rate Value (LE)
    ///   [2 bytes]    — Energy Expended (uint16 LE) — skipped if bit 4 set
    ///   [2 bytes…]   — RR-Interval(s) (uint16 LE, units: 1/1024 s each)
    static func parse(_ data: Data) throws -> HRMeasurement {
        guard data.count >= 2 else { throw ParseError.tooShort }

        let flags = data[0]
        let isUInt16Format = (flags & 0x01) != 0
        let contactBits   = (flags >> 1) & 0x03
        let energyPresent = (flags & 0x10) != 0
        let rrPresent     = (flags & 0x20) != 0

        // Sensor contact: bits [2:1]. Value 2 = not detected, 3 = detected.
        let contactStatus: Bool?
        switch contactBits {
        case 2: contactStatus = false
        case 3: contactStatus = true
        default: contactStatus = nil
        }

        var offset = 1

        // Heart rate value
        let heartRate: Int
        if isUInt16Format {
            guard data.count >= offset + 2 else { throw ParseError.tooShort }
            heartRate = Int(data[offset]) | (Int(data[offset + 1]) << 8)
            offset += 2
        } else {
            heartRate = Int(data[offset])
            offset += 1
        }

        guard heartRate > 0 else {
            throw ParseError.invalidFormat("Heart rate value is zero")
        }

        // Skip Energy Expended (uint16) if present
        if energyPresent {
            guard data.count >= offset + 2 else { throw ParseError.tooShort }
            offset += 2
        }

        // RR intervals (uint16 LE each, unit = 1/1024 seconds)
        var rrIntervals: [Double] = []
        if rrPresent {
            while offset + 1 < data.count {
                let raw = Int(data[offset]) | (Int(data[offset + 1]) << 8)
                let seconds = Double(raw) / 1024.0
                rrIntervals.append(seconds)
                offset += 2
            }
        }

        return HRMeasurement(
            heartRate: heartRate,
            rrIntervals: rrIntervals,
            contactStatus: contactStatus
        )
    }
}
