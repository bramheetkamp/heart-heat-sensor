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

    /// A short, localized, user-facing message suitable for auth screens.
    /// Maps low-level/server errors to translated strings (see Localizable.strings).
    var userFacingMessage: String {
        switch self {
        case .networkUnavailable:
            return NSLocalizedString("ERROR_NETWORK_UNAVAILABLE", comment: "Backend unreachable")
        case .serverError(let code, let body):
            return NSLocalizedString(Self.localizationKey(forStatus: code, body: body),
                                     comment: "Server-side auth error")
        case .noToken, .invalidURL, .decodingError:
            return NSLocalizedString("ERROR_GENERIC", comment: "Generic error")
        }
    }

    /// Translate a backend `{ "error": "..." }` response into a Localizable.strings key.
    private static func localizationKey(forStatus code: Int, body: String) -> String {
        let serverError = (try? JSONDecoder().decode([String: String].self, from: Data(body.utf8)))?["error"] ?? body
        let normalized = serverError.lowercased()
        if normalized.contains("invalid credentials") {
            return "ERROR_INVALID_CREDENTIALS"
        }
        if normalized.contains("already registered") {
            return "ERROR_EMAIL_ALREADY_REGISTERED"
        }
        if code == 401 {
            return "ERROR_INVALID_CREDENTIALS"
        }
        return "ERROR_GENERIC"
    }
}

/// Convert any error thrown during auth into a localized, user-facing message.
func authErrorMessage(_ error: Error) -> String {
    if let syncError = error as? SyncError {
        return syncError.userFacingMessage
    }
    return NSLocalizedString("ERROR_GENERIC", comment: "Generic error")
}

// MARK: - API Models

private struct AuthRequest: Encodable {
    let email: String
    let password: String
}

private struct AuthResponse: Decodable {
    let token: String
}

/// Wire format for `POST /readings/batch`. Field names, snake_case, the numeric
/// (Unix-ms) timestamp, the site mapping, and the ms RR units all match the
/// backend zod schema exactly — see backend/src/routes/readings.ts and
/// docs/BLE_CONTRACT.md. Do not rename without updating the backend in lockstep.
private struct ReadingPayload: Encodable {
    let id: String
    let device_id: String
    let timestamp: Int            // Unix milliseconds
    let heart_rate: Int?
    let rr_intervals: [Double]    // milliseconds (Reading stores seconds)
    let temp_site1: Double?       // core
    let temp_site2: Double?       // skin
    let eda: Double?              // skin conductance, µS
    let activity: String?         // "rest" | "active" | "sleep"; nil when unknown
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

        let payloads = readings.map { r in
            // Backend enum is rest|active|sleep; map .unknown → nil so temp-only
            // BodyTempSensor readings still validate.
            let activity: String? = (r.activity == .unknown) ? nil : r.activity.rawValue
            return ReadingPayload(
                id: r.id.uuidString,
                device_id: r.deviceId.isEmpty ? "LIVE" : r.deviceId,
                timestamp: Int((r.timestamp.timeIntervalSince1970 * 1000).rounded()),
                heart_rate: r.heartRate,
                rr_intervals: r.rrIntervals.map { $0 * 1000.0 },  // s → ms
                temp_site1: r.tempCore,
                temp_site2: r.tempSkin,
                eda: r.eda,
                activity: activity
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
