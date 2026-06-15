import XCTest
import Foundation
@testable import HeartRate

/// Tests for the *pure* parts of the on-device summary service — snapshot
/// derivation and prompt construction. The Foundation Models call itself is not
/// exercised here (it needs the on-device model at runtime); these cover the
/// data we feed it, which is where correctness bugs would hide.
final class HealthSummaryServiceTests: XCTestCase {

    private func makeReading(
        timestamp: Date,
        hr: Int? = 60,
        rr: [Double] = [0.90, 0.92, 0.88],
        tempCore: Double? = 36.7,
        tempSkin: Double? = 33.0,
        eda: Double? = nil,
        activity: Reading.ActivityLevel = .rest
    ) -> Reading {
        let r = Reading()
        r.timestamp = timestamp
        r.heartRate = hr
        r.rrIntervals = rr
        r.tempCore = tempCore
        r.tempSkin = tempSkin
        r.eda = eda
        r.activity = activity
        r.deviceId = "test"
        return r
    }

    func testSnapshotUsesNewestReadingForLatestValues() {
        let now = Date()
        let readings = [
            makeReading(timestamp: now.addingTimeInterval(-3600), hr: 55, tempCore: 36.5),
            makeReading(timestamp: now, hr: 72, tempCore: 37.1)   // newest
        ]
        let snap = HealthSummaryService.snapshot(readings: readings, warnings: [], profile: UserProfile())

        XCTAssertEqual(snap.latestHR, 72)
        XCTAssertEqual(snap.latestCoreTemp ?? 0, 37.1, accuracy: 0.001)
    }

    func testSnapshotCarriesActiveWarningsAndIgnoresResolved() {
        let active = HealthWarning(
            id: UUID(), type: .overheating, firedAt: Date(), resolvedAt: nil,
            title: "Overheating Alert", message: "Core temp high.",
            context: .init(triggerValues: [:], baselineValues: [:], trendValues: [], explanation: ""),
            deepLinkPath: "/warnings/overheating"
        )
        let resolved = HealthWarning(
            id: UUID(), type: .gettingSick, firedAt: Date(), resolvedAt: Date(),
            title: "Old", message: "Resolved.",
            context: .init(triggerValues: [:], baselineValues: [:], trendValues: [], explanation: ""),
            deepLinkPath: "/warnings/getting-sick"
        )
        let snap = HealthSummaryService.snapshot(
            readings: [makeReading(timestamp: Date())],
            warnings: [active, resolved],
            profile: UserProfile()
        )

        XCTAssertEqual(snap.activeWarnings.count, 1)
        XCTAssertTrue(snap.activeWarnings.first?.contains("Overheating Alert") == true)
    }

    func testPromptReportsNoFlagsWhenHealthy() {
        let snap = HealthSummaryService.snapshot(
            readings: [makeReading(timestamp: Date())],
            warnings: [],
            profile: UserProfile()
        )
        let prompt = HealthSummaryService.buildPrompt(snapshot: snap)

        XCTAssertTrue(prompt.contains("Active wellness flags: none"))
        XCTAssertTrue(prompt.contains("Heart rate:"))
    }

    func testPromptListsActiveWarnings() {
        var snap = HealthSummaryService.snapshot(
            readings: [makeReading(timestamp: Date())],
            warnings: [],
            profile: UserProfile()
        )
        snap.activeWarnings = ["You May Be Getting Sick: HR elevated."]
        let prompt = HealthSummaryService.buildPrompt(snapshot: snap)

        XCTAssertTrue(prompt.contains("You May Be Getting Sick"))
        XCTAssertFalse(prompt.contains("Active wellness flags: none"))
    }

    func testInstructionsForbidMedicalFraming() {
        // Guardrail: the system instructions must keep the model in wellness mode.
        XCTAssertTrue(HealthSummaryService.instructions.contains("Never diagnose"))
        XCTAssertTrue(HealthSummaryService.instructions.lowercased().contains("wellness"))
    }
}
