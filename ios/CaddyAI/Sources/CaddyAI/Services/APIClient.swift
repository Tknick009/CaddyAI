import Foundation
import CaddyAICore

/// Thin wrapper around the CaddyAI backend. All calls use the shared
/// snake-case JSON coder from `CaddyAICore`.
struct APIClient {
    enum APIError: Error, LocalizedError {
        case transport(Error)
        case http(Int, String)
        case decoding(Error)

        var errorDescription: String? {
            switch self {
            case .transport(let e): return "Network: \(e.localizedDescription)"
            case .http(let code, let body): return "HTTP \(code): \(body)"
            case .decoding(let e): return "Decoding: \(e.localizedDescription)"
            }
        }
    }

    let baseURL: URL
    let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func coachSwing(_ metrics: SwingMetrics) async throws -> CoachingReport {
        try await request(
            path: "/coach/swing",
            method: "POST",
            body: metrics,
            decode: CoachingReport.self
        )
    }

    func recommend(_ request: CaddyRecommendRequest) async throws -> CaddyRecommendation {
        try await self.request(
            path: "/caddy/recommend",
            method: "POST",
            body: request,
            decode: CaddyRecommendation.self
        )
    }

    func putBag(_ bag: Bag) async throws -> Bag {
        try await request(path: "/bag", method: "PUT", body: bag, decode: Bag.self)
    }

    func getBag() async throws -> Bag {
        try await request(path: "/bag", method: "GET", body: Empty?.none, decode: Bag.self)
    }

    func garminStatus() async throws -> GarminStatus {
        try await request(path: "/garmin/status", method: "GET", body: Empty?.none, decode: GarminStatus.self)
    }

    // MARK: - Private

    private func request<Body: Encodable, Out: Decodable>(
        path: String,
        method: String,
        body: Body?,
        decode: Out.Type
    ) async throws -> Out {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body {
            do {
                req.httpBody = try CaddyAIJSON.encoder.encode(body)
            } catch {
                throw APIError.decoding(error)
            }
        }
        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await session.data(for: req)
        } catch {
            throw APIError.transport(error)
        }
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        do {
            return try CaddyAIJSON.decoder.decode(Out.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }
}

private struct Empty: Codable {}

struct CaddyRecommendRequest: Codable {
    var targetDistanceYards: Double
    var elevationChangeFt: Double
    var windSpeedMph: Double
    var windDirectionDeg: Double
    var lie: Lie
    var pinPosition: PinPosition?
    var shotShapePreference: ShotShape?
    var avoidLeft: Bool
    var avoidRight: Bool
    var mustCarryYards: Double?
    var bag: Bag?

    init(context: ShotContext, bag: Bag?) {
        self.targetDistanceYards = context.targetDistanceYards
        self.elevationChangeFt = context.elevationChangeFt
        self.windSpeedMph = context.windSpeedMph
        self.windDirectionDeg = context.windDirectionDeg
        self.lie = context.lie
        self.pinPosition = context.pinPosition
        self.shotShapePreference = context.shotShapePreference
        self.avoidLeft = context.avoidLeft
        self.avoidRight = context.avoidRight
        self.mustCarryYards = context.mustCarryYards
        self.bag = bag
    }
}

struct GarminStatus: Codable {
    let configured: Bool
    let note: String
}
