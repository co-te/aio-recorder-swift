//
//  MinerAPI.swift
//  TwitchMiner
//
//  Typed client for the Twitch Channel Points Miner webui (FastAPI).
//  Auth: Bearer token on every mutating/read route. Live state arrives
//  over /ws as {"type":"state","data":[streamer...]} pushed every 15s.
//

import Foundation

// MARK: - Models

struct StreamerState: Identifiable, Decodable {
    let username: String
    let points: Int
    let isOnline: Bool
    let stream: StreamInfo?
    let pfp: String

    var id: String { username }

    enum CodingKeys: String, CodingKey {
        case username, points, pfp
        case isOnline = "is_online"
        case stream
    }

    var title: String { stream?.title ?? "" }
    var game: String { stream?.game ?? "" }
}

struct StreamInfo: Decodable {
    let title: String?
    let game: String?
}

struct MinerStatus: Decodable {
    let running: Bool
}

struct StreamerFull: Identifiable, Decodable {
    let username: String
    let settings: BetSettings
    let points: Int
    let isOnline: Bool
    let stream: StreamInfo?

    var id: String { username }

    enum CodingKeys: String, CodingKey {
        case username, settings, points
        case isOnline = "is_online"
        case stream
    }
}

struct BetSettings: Codable {
    var make_predictions: Bool
    var follow_raid: Bool
    var claim_drops: Bool
    var claim_moments: Bool
    var watch_streak: Bool
    var community_goals: Bool
    var chat: String
    var bet: BetConfig
}

struct BetConfig: Codable {
    var strategy: String
    var percentage: Int
    var stealth_mode: Bool
    var percentage_gap: Int
    var max_points: Int
    var delay_mode: String
    var delay: Int
    var minimum_points: Int
    var filter_condition: FilterCondition
}

struct FilterCondition: Codable {
    var by: String
    var `where`: String
    var value: Int

    enum CodingKeys: String, CodingKey {
        case by
        case `where` = "where"
        case value
    }
}

// APIError lives in Shared.swift (single definition for all clients).

// MARK: - Settings

struct MinerSettings: Equatable {
    var host: String
    var port: Int
    var token: String
    var refreshSeconds: Int

    static let defaults = MinerSettings(host: "", port: 8000, token: "", refreshSeconds: 10)

    var baseURL: String { "http://\(host):\(port)" }

    static let hostKey = "miner_host"
    static let portKey = "miner_port"
    static let tokenKey = "miner_token"
    static let refreshKey = "miner_refresh_seconds"

    static func load() -> MinerSettings {
        let d = UserDefaults.standard
        return MinerSettings(
            host: d.string(forKey: hostKey) ?? defaults.host,
            port: d.object(forKey: portKey) as? Int ?? defaults.port,
            token: d.string(forKey: tokenKey) ?? "",
            refreshSeconds: d.object(forKey: refreshKey) as? Int ?? defaults.refreshSeconds
        )
    }

    func save() {
        let d = UserDefaults.standard
        d.set(host, forKey: Self.hostKey)
        d.set(port, forKey: Self.portKey)
        d.set(token, forKey: Self.tokenKey)
        d.set(refreshSeconds, forKey: Self.refreshKey)
    }
}

// MARK: - API

final class MinerAPI {
    let settings: MinerSettings
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(settings: MinerSettings) {
        self.settings = settings
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 10
        session = URLSession(configuration: cfg)
    }

    private var headers: [String: String] {
        var h = ["Content-Type": "application/json"]
        if !settings.token.isEmpty { h["Authorization"] = "Bearer \(settings.token)" }
        return h
    }

    private func url(_ path: String, _ query: [String: String] = [:]) throws -> URL {
        guard var comps = URLComponents(string: settings.baseURL + path) else {
            throw APIError(statusCode: 0, message: "Invalid URL")
        }
        if !query.isEmpty {
            comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let u = comps.url else {
            throw APIError(statusCode: 0, message: "Invalid URL")
        }
        return u
    }

    private func request(_ method: String, _ path: String, query: [String: String] = [:], body: [String: Any]? = nil) throws -> URLRequest {
        var req = URLRequest(url: try url(path, query))
        req.httpMethod = method
        req.allHTTPHeaderFields = headers
        if let body { req.httpBody = try? JSONSerialization.data(withJSONObject: body) }
        return req
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try decoder.decode(type, from: data) }
        catch let e as DecodingError {
            throw APIError(statusCode: 200, message: "Bad response shape: \(e)")
        }
    }

    private func send<T: Decodable>(_ type: T.Type, _ req: URLRequest) async throws -> T {
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw APIError(statusCode: 0, message: "No response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let msg = (try? decoder.decode([String: String].self, from: data))?["detail"]
            throw APIError(statusCode: http.statusCode, message: msg ?? "")
        }
        return try decode(type, from: data)
    }

    // ---- endpoints ----

    func minerStatus() async throws -> Bool {
        let r: MinerStatus = try await send(MinerStatus.self, try request("GET", "/api/miner-status"))
        return r.running
    }

    /// Enriched streamer list (points come from parsed logs; may lag WS state).
    func streamers() async throws -> [StreamerFull] {
        try await send([StreamerFull].self, try request("GET", "/api/streamers"))
    }

    func addStreamer(_ username: String) async throws {
        _ = try await send([String: Bool].self,
            try request("POST", "/api/streamers", body: ["username": username]))
    }

    func removeStreamer(_ username: String) async throws {
        let safeUser = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        _ = try await send([String: Bool].self,
            try request("DELETE", "/api/streamers/\(safeUser)"))
    }

    func updateStreamerSettings(_ username: String, _ settings: BetSettings) async throws {
        let enc = JSONEncoder()
        let payload = try JSONSerialization.jsonObject(with: enc.encode(["settings": settings]))
        let safeUser = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        _ = try await send([String: Bool].self,
            try request("PATCH", "/api/streamers/\(safeUser)", body: payload as? [String: Any]))
    }

    func refreshPoints() async throws {
        _ = try await send([String: Bool].self, try request("POST", "/api/refresh-points"))
    }

    func applyRestart() async throws {
        // FastAPI returns null or terminates the process immediately (SIGTERM to PID 1)
        do {
            _ = try await session.data(for: try request("POST", "/api/apply-restart"))
        } catch {
            // Container restart drops connection — this is expected behavior
        }
    }

    func recentLogs(lines: Int = 60, streamer: String? = nil) async throws -> [String] {
        var q = ["lines": String(lines)]
        if let s = streamer { q["streamer"] = s }
        struct LogResp: Decodable { let lines: [String] }
        let r: LogResp = try await send(LogResp.self, try request("GET", "/api/logs/recent", query: q))
        return r.lines
    }

    func globalSettings() async throws -> [String: Any] {
        let (data, resp) = try await session.data(for: try request("GET", "/api/settings"))
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError(statusCode: (resp as? HTTPURLResponse)?.statusCode ?? 0, message: "Failed to load settings")
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    func saveGlobalSettings(_ obj: [String: Any]) async throws {
        _ = try await send([String: Bool].self,
            try request("PUT", "/api/settings", body: obj))
    }
}

// MARK: - WS live state

extension MinerAPI {
    /// Reconnecting /ws stream: server pushes full state on connect and
    /// every 15s. Client pings to keep it interactive.
    func stateStream() -> AsyncStream<[StreamerState]> {
        AsyncStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    guard !settings.host.isEmpty,
                          let wsURL = URL(string: "ws://\(settings.host):\(settings.port)/ws") else {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        continue
                    }
                    var activeWS: URLSessionWebSocketTask?
                    do {
                        let ws = URLSession.shared.webSocketTask(with: wsURL)
                        activeWS = ws
                        ws.resume()
                        // drain initial state + updates
                        while let msg = try? await ws.receive() {
                            guard case .string(let text) = msg,
                                  let obj = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
                                  obj["type"] as? String == "state",
                                  let arr = obj["data"] as? [[String: Any]]
                            else { continue }
                            let jsonData = try JSONSerialization.data(withJSONObject: arr)
                            let list = try decoder.decode([StreamerState].self, from: jsonData)
                            continuation.yield(list)
                        }
                    } catch { /* reconnect below */ }
                    activeWS?.cancel(with: .goingAway, reason: nil)
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
