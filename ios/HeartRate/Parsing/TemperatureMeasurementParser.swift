import Foundation

// MARK: - Temperature Measurement Parser

/// Parses Bluetooth Health Thermometer Temperature Measurement characteristic (0x2A1C)
/// per the Bluetooth SIG specification.
enum TemperatureMeasurementParser {

    /// Parse raw characteristic data into a TemperatureMeasurement.
    ///
    /// Byte 0 — Flags:
    ///   bit 0:  Temperature Units (0 = Celsius, 1 = Fahrenheit)
    ///   bit 1:  Time Stamp present
    ///   bit 2:  Temperature Type present
    ///
    /// Bytes 1–4:  IEEE-11073 FLOAT (32-bit):
    ///             top byte = signed exponent (int8)
    ///             lower 3 bytes = signed mantissa (int24 LE)
    ///             value = mantissa × 10^exponent
    ///
    /// Bytes 5–11 (optional): Time Stamp (7 bytes)
    /// Byte 12   (optional):  Temperature Type (1 byte)
    static func parse(_ data: Data, siteHint: TemperatureSite = .unknown) throws -> TemperatureMeasurement {
        guard data.count >= 5 else { throw ParseError.tooShort }

        let flags = data[0]
        let isFahrenheit     = (flags & 0x01) != 0
        let timeStampPresent = (flags & 0x02) != 0
        let typePresent      = (flags & 0x04) != 0

        // Parse IEEE-11073 FLOAT at offset 1
        var celsiusValue = ieee11073ToDouble(data, offset: 1)

        // Convert Fahrenheit → Celsius if needed
        if isFahrenheit {
            celsiusValue = (celsiusValue - 32.0) * 5.0 / 9.0
        }

        // Advance past the float and optional timestamp
        var offset = 5
        if timeStampPresent {
            offset += 7  // Date/Time is 7 bytes per spec
        }

        // Determine temperature site
        var site: TemperatureSite = siteHint
        if typePresent && offset < data.count {
            let typeCode = data[offset]
            site = temperatureSite(from: typeCode)
        }

        let siteLabel = (site == .unknown) ? "Unknown" : site.rawValue

        return TemperatureMeasurement(
            value: celsiusValue,
            siteLabel: siteLabel,
            site: site
        )
    }

    /// Decode an IEEE-11073 32-bit FLOAT from `data` at `offset`.
    ///
    /// Format: [exponent (int8)] [mantissa low] [mantissa mid] [mantissa high]
    /// Value = mantissa × 10^exponent
    static func ieee11073ToDouble(_ data: Data, offset: Int) -> Double {
        guard data.count >= offset + 4 else { return Double.nan }

        // Top byte is the signed exponent
        let exponentByte = Int8(bitPattern: data[offset + 3])
        let exponent = Int(exponentByte)

        // Lower 3 bytes are the signed 24-bit mantissa (little-endian)
        let m0 = Int(data[offset])
        let m1 = Int(data[offset + 1])
        let m2 = Int(data[offset + 2])

        var mantissa = m0 | (m1 << 8) | (m2 << 16)

        // Sign-extend from 24 bits to Int
        if mantissa & 0x800000 != 0 {
            mantissa |= ~0xFFFFFF  // extend sign bit
        }

        let value = Double(mantissa) * pow(10.0, Double(exponent))
        return value
    }

    // MARK: - Private Helpers

    /// Map the Temperature Type characteristic value to a TemperatureSite.
    /// Per Bluetooth SIG Temperature Type characteristic (0x2A1D):
    ///   1 = Armpit, 2 = Body (general), 3 = Ear, 4 = Finger
    ///   5 = Gastro-intestinal Tract, 6 = Mouth, 7 = Rectum
    ///   8 = Toe, 9 = Tympanum (Ear drum)
    private static func temperatureSite(from typeCode: UInt8) -> TemperatureSite {
        switch typeCode {
        case 1, 3, 4, 6, 8, 9:
            return .skin
        case 2, 5, 7:
            return .core
        default:
            return .unknown
        }
    }
}
