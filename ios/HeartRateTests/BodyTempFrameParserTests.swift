import XCTest
@testable import HeartRate

/// Byte-level tests for the BodyTempSensor custom-service parser (Profile B).
/// The firmware sends native little-endian IEEE-754 float32 for each scalar
/// characteristic — see docs/BLE_CONTRACT.md.
final class BodyTempFrameParserTests: XCTestCase {

    func test_parseFloat32LE_decodesKnownBitPatterns() throws {
        // 1.0f = 0x3F800000 → LE bytes 00 00 80 3F
        XCTAssertEqual(try BodyTempFrameParser.parseFloat32LE(Data([0x00, 0x00, 0x80, 0x3F])), 1.0)
        // 37.0f = 0x42140000 → LE bytes 00 00 14 42
        XCTAssertEqual(try BodyTempFrameParser.parseFloat32LE(Data([0x00, 0x00, 0x14, 0x42])), 37.0)
        // 5.0f = 0x40A00000 → LE bytes 00 00 A0 40
        XCTAssertEqual(try BodyTempFrameParser.parseFloat32LE(Data([0x00, 0x00, 0xA0, 0x40])), 5.0)
    }

    func test_parseFloat32LE_handlesNonZeroSliceStartIndex() throws {
        // A Data slice does not necessarily start at index 0; the parser must
        // read off startIndex, not a hard-coded 0.
        let padded = Data([0xFF, 0xFF, 0x00, 0x00, 0x80, 0x3F]) // 1.0f after 2 junk bytes
        let slice = padded.suffix(4)
        XCTAssertEqual(try BodyTempFrameParser.parseFloat32LE(slice), 1.0)
    }

    func test_parseFloat32LE_throwsOnShortData() {
        XCTAssertThrowsError(try BodyTempFrameParser.parseFloat32LE(Data([0x00, 0x00, 0x80])))
    }

    func test_parseFloat32LE_throwsOnNonFinite() {
        // +Inf = 0x7F800000 → LE bytes 00 00 80 7F
        XCTAssertThrowsError(try BodyTempFrameParser.parseFloat32LE(Data([0x00, 0x00, 0x80, 0x7F])))
    }

    func test_parseTemperature_mapsSiteAndValue() throws {
        let core = try BodyTempFrameParser.parseTemperature(Data([0x00, 0x00, 0x14, 0x42]), site: .core)
        XCTAssertEqual(core.site, .core)
        XCTAssertEqual(core.value, 37.0, accuracy: 0.0001)

        let skin = try BodyTempFrameParser.parseTemperature(Data([0x00, 0x00, 0xA0, 0x40]), site: .skin)
        XCTAssertEqual(skin.site, .skin)
        XCTAssertEqual(skin.value, 5.0, accuracy: 0.0001)
    }

    func test_parseEDA_returnsMicrosiemens() throws {
        let eda = try BodyTempFrameParser.parseEDA(Data([0x00, 0x00, 0xA0, 0x40]))
        XCTAssertEqual(eda.conductance, 5.0, accuracy: 0.0001)
    }
}
