import XCTest
@testable import HeartRate

final class HRMeasurementParserTests: XCTestCase {

    // MARK: - 8-bit HR, no RR

    func test_uint8HR_noRR() throws {
        // Flags: 0b00000000 = uint8 format, no contact, no energy, no RR
        // HR: 72
        let data = Data([0x00, 0x48])
        let result = try HRMeasurementParser.parse(data)
        XCTAssertEqual(result.heartRate, 72)
        XCTAssertTrue(result.rrIntervals.isEmpty)
    }

    // MARK: - 16-bit HR, no RR

    func test_uint16HR_noRR() throws {
        // Flags: 0b00000001 = uint16 format
        // HR: 200 = 0x00C8 LE → bytes [0xC8, 0x00]
        let data = Data([0x01, 0xC8, 0x00])
        let result = try HRMeasurementParser.parse(data)
        XCTAssertEqual(result.heartRate, 200)
        XCTAssertTrue(result.rrIntervals.isEmpty)
    }

    // MARK: - 8-bit HR + RR intervals

    func test_uint8HR_withRR() throws {
        // Flags: 0b00010000 = uint8 format, RR intervals present
        // HR: 65
        // RR1: 938 (0x03AA LE) = 938/1024 ≈ 0.9160 s
        // RR2: 952 (0x03B8 LE) = 952/1024 ≈ 0.9297 s
        let data = Data([0x10, 0x41, 0xAA, 0x03, 0xB8, 0x03])
        let result = try HRMeasurementParser.parse(data)
        XCTAssertEqual(result.heartRate, 65)
        XCTAssertEqual(result.rrIntervals.count, 2)
        XCTAssertEqual(result.rrIntervals[0], 938.0 / 1024.0, accuracy: 0.0001)
        XCTAssertEqual(result.rrIntervals[1], 952.0 / 1024.0, accuracy: 0.0001)
    }

    // MARK: - With energy expended (must be skipped properly)

    func test_uint8HR_energyPresent_noRR() throws {
        // Flags: 0b00001000 = uint8 format, energy expended present
        // HR: 80, Energy: 500 (0x01F4 LE)
        let data = Data([0x08, 0x50, 0xF4, 0x01])
        let result = try HRMeasurementParser.parse(data)
        XCTAssertEqual(result.heartRate, 80)
        XCTAssertTrue(result.rrIntervals.isEmpty)
    }

    // MARK: - 16-bit HR + energy + RR

    func test_uint16HR_energy_RR() throws {
        // Flags: 0b00011001 = uint16 HR + energy present + RR present
        // HR: 120 (0x0078 LE)
        // Energy: 200 (0x00C8 LE)
        // RR: 512 (0x0200 LE) = 512/1024 = 0.5000 s
        let data = Data([0x19, 0x78, 0x00, 0xC8, 0x00, 0x00, 0x02])
        let result = try HRMeasurementParser.parse(data)
        XCTAssertEqual(result.heartRate, 120)
        XCTAssertEqual(result.rrIntervals.count, 1)
        XCTAssertEqual(result.rrIntervals[0], 0.5, accuracy: 0.0001)
    }

    // MARK: - Error cases

    func test_emptyData_throws() {
        XCTAssertThrowsError(try HRMeasurementParser.parse(Data())) { error in
            if case ParseError.tooShort = error { } else {
                XCTFail("Expected tooShort, got \(error)")
            }
        }
    }

    func test_oneByte_throws() {
        XCTAssertThrowsError(try HRMeasurementParser.parse(Data([0x00]))) { error in
            if case ParseError.tooShort = error { } else {
                XCTFail("Expected tooShort, got \(error)")
            }
        }
    }

    // MARK: - Sensor contact

    func test_contactNotSupported() throws {
        // Flags: 0b00000000 = contact bits both 0 → not supported → nil
        let data = Data([0x00, 0x70])
        let result = try HRMeasurementParser.parse(data)
        XCTAssertNil(result.contactStatus)
    }

    func test_contactDetected() throws {
        // Flags: 0b00000110 = contact supported + detected
        let data = Data([0x06, 0x70])
        let result = try HRMeasurementParser.parse(data)
        XCTAssertEqual(result.contactStatus, true)
    }

    func test_contactNotDetected() throws {
        // Flags: 0b00000100 = contact supported, not detected
        let data = Data([0x04, 0x70])
        let result = try HRMeasurementParser.parse(data)
        XCTAssertEqual(result.contactStatus, false)
    }
}
