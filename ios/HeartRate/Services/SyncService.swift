import Foundation

// MARK: - SyncError

enum SyncError: Error, LocalizedError {
    case noToken
    case invalidURL(String)
    case serverError(statusCode: Int, body: String)
    case decodingError(String)
    case networkUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .noToken:
            return "No authentication token. Please log in first."
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .serverError(let code, let body):
            return "Server returned \(code): \(body)"
        case .decodingError(let detail):
            return "Failed to decode server response: \(detail)"
        case .networkUnavailable(let reason):
            return "Network unavailable: \(reason)"
        }
    }
}

// MARK: - API Models

private struct AuthRequest: Encodable {
    let email: String
    let password: String
}

private struct AuthResponse: Decodable {
    let token: String
}

private struct ReadingPayload: Encodable {
    let id: String
    let timestamp: String
    let heartRate: Int?
    let rrIntervals: [Double]
    let tempCore: Double?
    let tempSkin: Double?
    let activity: String
    let deviceId: String
}

private struct UploadBatchRequest: Encodable {
    let readings: [ReadingPayload]
}

private struct WarningResponse: Decodable {
    let id: String
    let type: String
    let firedAt: String
    let resolvedAt: String?
    let title: String
    let message: String
    let deepLinkPath: String
    let triggerValues: [String: Double]?
    let baselineValues: [String: Double]?
    let trendValues: [Double]?
    let explanation: String?
}

// MARK: - SyncService

@MainActor
final class SyncService: ObservableObject {

    // MARK: - Base URL

    static let baseURL: String = {
        ProcessInfo.processInfo.environment["API_BASE_URL"] ?? "http://localhost:3100"
    }()

    // MARK: - Published State

    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var syncError: String?

    // MARK: - Private

    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    // MARK: - Init

    init(session: URLSession = .shared) {
        self.session = session

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec
    }

    // MARK: - Auth

    func register(email: String, password: String) async throws -> String {
        let body = AuthRequest(email: email, password: password)
        return try await postAuth(path: "/auth/register", body: body)
    }

    func login(email: String, password: String) async throws -> String {
        let body = AuthRequest(email: email, password: password)
        return try await postAuth(path: "/auth/login", body: body)
    }

    // MARK: - Data Upload

    /// Upload a batch of readings to the backend. Returns early if no token provided.
    func uploadBatch(readings: [Reading], token: String) async throws {
        guard !token.isEmpty else { throw SyncError.noToken }
        guard !readings.isEmpty else { return }

        isSyncing = true
        syncError = nil
        defer { isSyncing = false }

        let iso = ISO8601DateFormatter()
        let payloads = readings.map { r in
            ReadingPayload(
                id: r.id.uuidString,
                timestamp: iso.string(from: r.timestamp),
                heartRate: r.heartRate,
                rrIntervals: r.rrIntervals,
                tempCore: r.tempCore,
                tempSkin: r.tempSkin,
                activity: r.activity.rawValue,
                deviceId: r.deviceId
            )
        }

        let body = UploadBatchRequest(readings: payloads)
        let url = try makeURL(path: "/readings/batch")
        var request = authorizedRequest(url: url, token: token)
        request.httpMethod = "POST"
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await performRequest(request)
        try validateResponse(data: data, response: response)

        lastSyncDate = Date()
    }

    // MARK: - Warnings Fetch

    /// Fetch health warnings computed by the backend. Returns early if no token provided.
    func fetchWarnings(token: String) async throws -> [HealthWarning] {
        guard !token.isEmpty else { throw SyncError.noToken }

        let url = try makeURL(path: "/warnings")
        let request = authorizedRequest(url: url, token: token)
        let (data, response) = try await performRequest(request)
        try validateResponse(data: data, response: response)

        let raw = try decodeOrThrow([WarningResponse].self, from: data)
        return raw.compactMap { mapWarning($0) }
    }

    // MARK: - Future Extension Point

    // MARK: - Future: Garmin Health API Integration
    // func syncGarminData(token: String) async throws { fatalError("Not implemented") }

    // MARK: - Private Helpers

    private func postAuth(path: String, body: AuthRequest) async throws -> String {
        let url = try makeURL(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await performRequest(request)
        try validateResponse(data: data, response: response)

        let authResponse = try decodeOrThrow(AuthResponse.self, from: data)
        return authResponse.token
    }

    private func makeURL(path: String) throws -> URL {
        let urlString = SyncService.baseURL + path
        guard let url = URL(string: urlString) else {
            throw SyncError.invalidURL(urlString)
        }
        return url
    }

    private func authorizedRequest(url: URL, token: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let urlError as URLError {
            throw SyncError.networkUnavailable(urlError.localizedDescription)
        } catch {
            throw SyncError.networkUnavailable(error.localizedDescription)
        }
    }

    private func validateResponse(data: Data, response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else { return }
        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "(non-UTF8 body)"
            throw SyncError.serverError(statusCode: httpResponse.statusCode, body: body)
        }
    }

    private func decodeOrThrow<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw SyncError.decodingError(error.localizedDescription)
        }
    }

    private func mapWarning(_ raw: WarningResponse) -> HealthWarning? {
        guard let type = HealthWarning.WarningType(rawValue: raw.type),
              let id   = UUID(uuidString: raw.id) else { return nil }

        let iso = ISO8601DateFormatter()
        let firedAt    = iso.date(from: raw.firedAt) ?? Date()
        let resolvedAt = raw.resolvedAt.flatMap { iso.date(from: $0) }

        return HealthWarning(
            id: id,
            type: type,
            firedAt: firedAt,
            resolvedAt: resolvedAt,
            title: raw.title,
            message: raw.message,
            context: HealthWarning.WarningContext(
                triggerValues:  raw.triggerValues  ?? [:],
                baselineValues: raw.baselineValues ?? [:],
                trendValues:    raw.trendValues    ?? [],
                explanation:    raw.explanation    ?? ""
            ),
            deepLinkPath: raw.deepLinkPath
        )
    }
}
