import Foundation
import SwiftData

@MainActor
final class DataStore: ObservableObject {

    let container: ModelContainer

    // MARK: - Init

    init(inMemory: Bool = false) {
        let schema = Schema([Reading.self, UserProfile.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Fall back to an in-memory store so the app still launches;
            // a real app might surface this error to the user.
            let fallbackConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            container = try! ModelContainer(for: schema, configurations: [fallbackConfig])
        }
    }

    // MARK: - Private Context

    private var context: ModelContext {
        container.mainContext
    }

    // MARK: - Reading CRUD

    /// Persist a new reading.
    func save(reading: Reading) throws {
        context.insert(reading)
        try context.save()
    }

    /// Persist many readings in a single transaction (one `context.save()`).
    /// Demo seeding inserts ~hundreds of rows at once; saving per-row would fire
    /// the dashboard's `@Query` (and its chart/recovery recompute) hundreds of
    /// times, which is the source of the scenario-switch lag.
    func save(readings: [Reading]) throws {
        guard !readings.isEmpty else { return }
        for reading in readings { context.insert(reading) }
        try context.save()
    }

    /// Delete all readings recorded by a given device id (used to clear demo
    /// data before re-seeding so scenarios don't accumulate or mix).
    func deleteReadings(deviceId: String) throws {
        let predicate = #Predicate<Reading> { $0.deviceId == deviceId }
        try context.delete(model: Reading.self, where: predicate)
        try context.save()
    }

    /// Drop readings older than `days` to bound on-device growth from a device
    /// that streams continuously (~every 5 s). Retention is kept generous so the
    /// 30-day warning baselines are never starved. Returns nothing; best-effort.
    @discardableResult
    func pruneReadings(olderThan days: Int) throws -> Bool {
        guard days > 0 else { return false }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let predicate = #Predicate<Reading> { $0.timestamp < cutoff }
        try context.delete(model: Reading.self, where: predicate)
        try context.save()
        return true
    }

    /// Fetch readings within an inclusive date range, sorted ascending.
    func readings(from startDate: Date, to endDate: Date) throws -> [Reading] {
        let predicate = #Predicate<Reading> { reading in
            reading.timestamp >= startDate && reading.timestamp <= endDate
        }
        let descriptor = FetchDescriptor<Reading>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        return try context.fetch(descriptor)
    }

    /// Fetch readings from the last N calendar days, sorted ascending.
    func recentReadings(days: Int) throws -> [Reading] {
        let cutoff = Calendar.current.date(
            byAdding: .day,
            value: -days,
            to: Date()
        ) ?? Date()
        return try readings(from: cutoff, to: Date())
    }

    /// Fetch the single UserProfile, creating one with defaults if none exists.
    func getOrCreateProfile() throws -> UserProfile {
        let descriptor = FetchDescriptor<UserProfile>()
        let profiles = try context.fetch(descriptor)
        if let existing = profiles.first {
            return existing
        }
        let newProfile = UserProfile()
        context.insert(newProfile)
        try context.save()
        return newProfile
    }

    /// Mark the given reading IDs as synced with the backend.
    func markAsSynced(ids: [UUID]) throws {
        guard !ids.isEmpty else { return }
        let idSet = Set(ids)
        let predicate = #Predicate<Reading> { reading in
            idSet.contains(reading.id)
        }
        let descriptor = FetchDescriptor<Reading>(predicate: predicate)
        let readings = try context.fetch(descriptor)
        for reading in readings {
            reading.synced = true
        }
        try context.save()
    }

    // MARK: - Unsynced Helpers

    /// All readings that have not yet been uploaded to the backend.
    func unsyncedReadings() throws -> [Reading] {
        let predicate = #Predicate<Reading> { reading in
            reading.synced == false
        }
        let descriptor = FetchDescriptor<Reading>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        return try context.fetch(descriptor)
    }
}
