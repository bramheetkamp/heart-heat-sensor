import XCTest
@testable import HeartRate

final class TemperatureMeasurementParserTests: XCTestCase {

    // MARK: - IEEE-11073 float helper

    func test_ieee11073_positiveExponent() {
        // mantissa = 365, exponent = -2 → 3.65°C
        // Bytes (mantissa little-endian 3 bytes + exponent): [0x6D, 0x01, 0x00, 0xFE]
        // 0x0000016D = 365; exponent byte = 0xFE = -2 (int8)
        let data = Data([0x6D, 0x01, 0x00, 0xFE])
        let value = TemperatureMeasurementParser.ieee11073ToDouble(data, offset: 0)
        XCTAssertEqual(value, 3.65, accuracy: 0.001)
    }

    func test_ieee11073_zero_exponent() {
        // mantissa = 37, exponent = 0 → 37.0
        let data = Data([0x25, 0x00, 0x00, 0x00])
        let value = TemperatureMeasurementParser.ieee11073ToDouble(data, offset: 0)
        XCTAssertEqual(value, 37.0, accuracy: 0.001)
    }

    // MARK: - Full parse: Celsius, no extras

    func test_celsius_noTimestamp_noSite() throws {
        // Flags: 0x00 = Celsius, no timestamp, no temperature type
        // Temperature: 36.7°C → mantissa=367, exp=-1 → bytes [0x6F, 0x01, 0x00, 0xFF]
        let data = Data([0x00, 0x6F, 0x01, 0x00, 0xFF])
        let result = try TemperatureMeasurementParser.parse(data)
        XCTAssertEqual(result.value, 36.7, accuracy: 0.01)
    }

    // MARK: - Fahrenheit conversion

    func test_fahrenheit_converted_to_celsius() throws {
        // Flags: 0x01 = Fahrenheit
        // 98.6°F = 37.0°C
        // 98.6 → mantissa=986, exp=-1 → [0xDA, 0x03, 0x00, 0xFF]
        let data = Data([0x01, 0xDA, 0x03, 0x00, 0xFF])
        let result = try TemperatureMeasurementParser.parse(data)
        XCTAssertEqual(result.value, 37.0, accuracy: 0.1)
    }

    // MARK: - Temperature site hint fallback

    func test_siteHint_core() throws {
        let data = Data([0x00, 0x6F, 0x01, 0x00, 0xFF])
        let result = try TemperatureMeasurementParser.parse(data, siteHint: .core)
        XCTAssertEqual(result.site, .core)
        XCTAssertEqual(result.siteLabel, "Core")
    }

    func test_siteHint_skin() throws {
        let data = Data([0x00, 0x6F, 0x01, 0x00, 0xFF])
        let result = try TemperatureMeasurementParser.parse(data, siteHint: .skin)
        XCTAssertEqual(result.site, .skin)
        XCTAssertEqual(result.siteLabel, "Skin")
    }

    // MARK: - Error: too short

    func test_tooShort_throws() {
        XCTAssertThrowsError(try TemperatureMeasurementParser.parse(Data([0x00, 0x6F])))
    }

    // MARK: - Normal body temp range

    func test_normalBodyTemp_37c() throws {
        // 37.0°C → mantissa=3700, exp=-2 → [0x70, 0x0E, 0x00, 0xFE]
        let data = Data([0x00, 0x70, 0x0E, 0x00, 0xFE])
        let result = try TemperatureMeasurementParser.parse(data)
        XCTAssertEqual(result.value, 37.0, accuracy: 0.01)
    }

    func test_fever_38c5() throws {
        // 38.5°C → mantissa=3850, exp=-2 → [0x0A, 0x0F, 0x00, 0xFE]
        let data = Data([0x00, 0x0A, 0x0F, 0x00, 0xFE])
        let result = try TemperatureMeasurementParser.parse(data)
        XCTAssertEqual(result.value, 38.5, accuracy: 0.01)
    }
}
