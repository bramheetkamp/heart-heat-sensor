import Foundation

// MARK: - BodyTempSensor Custom-Service Parser

/// Decodes the scalar characteristics of the BodyTempSensor custom BLE service
/// (Profile B — see docs/BLE_CONTRACT.md). Each scalar characteristic
/// (`a0b40001` skin, `a0b40002` core, `a0b40003` EDA) carries one native
/// little-endian IEEE-754 single-precision float (4 bytes).
///
/// The firmware writes these from a little-endian Cortex-M, so the on-air byte
/// order is little-endian regardless of the phone's endianness. We reconstruct
/// the bit pattern explicitly rather than `memcpy`-ing, so this is correct on
/// any host.
enum BodyTempFrameParser {

    /// Decode a little-endian `float32` characteristic payload.
    /// - Throws: `ParseError.tooShort` if fewer than 4 bytes.
    ///           `ParseError.invalidFormat` if the value is NaN/infinite.
    static func parseFloat32LE(_ data: Data) throws -> Float {
        guard data.count >= 4 else { throw ParseError.tooShort }

        // Read the first 4 bytes as a little-endian UInt32 bit pattern. Index
        // off `startIndex` because a `Data` slice may not be zero-based.
        let b = data
        let i = b.startIndex
        let bits = UInt32(b[i])
            | (UInt32(b[i + 1]) << 8)
            | (UInt32(b[i + 2]) << 16)
            | (UInt32(b[i + 3]) << 24)

        let value = Float(bitPattern: bits)
        guard value.isFinite else {
            throw ParseError.invalidFormat("Non-finite float (bits=\(bits))")
        }
        return value
    }

    /// Decode a temperature characteristic (skin or core) into a
    /// `TemperatureMeasurement`. The `site` is supplied by the caller because it
    /// is implied by *which* characteristic the value came from, not by the
    /// payload itself.
    static func parseTemperature(_ data: Data, site: TemperatureSite) throws -> TemperatureMeasurement {
        let celsius = Double(try parseFloat32LE(data))
        return TemperatureMeasurement(value: celsius, siteLabel: site.rawValue, site: site)
    }

    /// Decode the EDA / skin-conductance characteristic into an `EDAMeasurement`.
    static func parseEDA(_ data: Data) throws -> EDAMeasurement {
        let microsiemens = Double(try parseFloat32LE(data))
        return EDAMeasurement(conductance: microsiemens)
    }
}
