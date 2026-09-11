//
//  TikAPI.swift
//  AIO — client for the TikTok/Twitch live-recorder (FastAPI, :8090).
//  Shapes verified live against /api/sources, /api/recordings, /api/settings.
//

import Foundation

// MARK: - Models

struct TikSource: Identifiable, Decodable {
    let id: String
    let platform: String
    let user: String
    let url: String?
    let interval: Int
    let duration: Int?
    let outputDir: String?
    let quality: String?
    let enabled: Bool
    let lastCheck: String?
    let currentlyLive: Bool
    let lastError: String?

    enum CodingKeys: String, CodingKey {
        case id, platform, user, url, interval, duration, quality, enabled
        case outputDir = "output_dir"
        case lastCheck = "last_check"
        case currentlyLive = "currently_live"
        case lastError = "last_error"
    }
}

struct TikRecording: Identifiable, Decodable {
    let id: String
    let platform: String
    let user: String
    let startTime: String?
    let elapsed: Double
    let sizeBytes: Int
    let status: String
    let error: String?
    let finalPath: String?
    let outputFile: String?

    enum CodingKeys: String, CodingKey {
        case id, platform, user, status, error
        case startTime = "start_time"
        case elapsed
        case sizeBytes = "size_bytes"
        case finalPath = "final_path"
        case outputFile = "output_file"
    }

    var displayPath: String { finalPath ?? outputFile ?? "" }
    var isActive: Bool { status == "recording" }
}

struct TikSettingsData: Decodable {
    var outputDir: String
    var defaultQuality: String
    var proxy: String
    var defaultDuration: Int?
    var defaultInterval: Int
    var autoConvert: Bool

    enum CodingKeys: String, CodingKey {
        case outputDir = "output_dir"
        case defaultQuality = "default_quality"
        case proxy
        case defaultDuration = "default_duration"
        case defaultInterval = "default_interval"
        case autoConvert = "auto_convert"
    }
}

// MARK: - Connection settings

struct TikSettings: Equatable {
    var host: String
    var port: Int

    static let defaults = TikSettings(host: "192.168.110.58", port: 8090)
    var baseURL: String { "http://\(host):\(port)" }

    static let hostKey = "tik_host"
    static let portKey = "tik_port"

    static func load() -> TikSettings {
        let d = UserDefaults.standard
        return TikSettings(
            host: d.string(forKey: hostKey) ?? defaults.host,
            port: d.object(forKey: portKey) as? Int ?? defaults.port)
    }

    func save() {
        let d = UserDefaults.standard
        d.set(host, forKey: Self.hostKey)
        d.set(port, forKey: Self.portKey)
    }
}

// MARK: - API

final class TikAPI {
    let settings: TikSettings
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(settings: TikSettings) {
        self.settings = settings
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15
        session = URLSession(configuration: cfg)
    }

    private func url(_ path: String, _ query: [String: String] = [:]) -> URL {
        var comps = URLComponents(string: settings.baseURL + path)!
        if !query.isEmpty {
            comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        return comps.url!
    }

    private func req(_ method: String, _ path: String,
                     query: [String: String] = [:],
                     json: [String: Any]? = nil) -> URLRequest {
        var r = URLRequest(url: url(path, query))
        r.httpMethod = method
        if let json {
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = try? JSONSerialization.data(withJSONObject: json)
        }
        return r
    }

    private func send<T: Decodable>(_ type: T.Type, _ r: URLRequest) async throws -> T {
        let (data, resp) = try await session.data(for: r)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw APIError(statusCode: code, message: (obj?["detail"] as? String) ?? "")
        }
        do {
            return try decoder.decode(type, from: data)
        } catch let e as DecodingError {
            throw APIError(statusCode: 200, message: "Bad response shape: \(e)")
        }
    }

    private func sendDict(_ r: URLRequest) async throws -> [String: Any] {
        let (data, resp) = try await session.data(for: r)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(code) else {
            throw APIError(statusCode: code, message: (obj["detail"] as? String) ?? "")
        }
        return obj
    }

    // ---- sources (monitors) ----

    func sources() async throws -> [TikSource] {
        struct Resp: Decodable { let sources: [TikSource] }
        return try await send(Resp.self, req("GET", "/api/sources")).sources
    }

    func addSource(platform: String, user: String, interval: Int = 5, quality: String = "best",
                   url: String? = nil, duration: Int? = nil, outputDir: String? = nil) async throws {
        var payload: [String: Any] = [
            "platform": platform, "user": user,
            "interval": interval, "quality": quality,
        ]
        if let url, !url.isEmpty { payload["url"] = url }
        if let duration { payload["duration"] = duration }
        if let outputDir, !outputDir.isEmpty { payload["output_dir"] = outputDir }
        _ = try await sendDict(req("POST", "/api/sources", json: payload))
    }

    func updateSource(_ id: String, enabled: Bool? = nil, interval: Int? = nil,
                       quality: String? = nil, duration: Int? = nil,
                       outputDir: String? = nil) async throws {
        var payload = [String: Any]()
        if let enabled { payload["enabled"] = enabled }
        if let interval { payload["interval"] = interval }
        if let quality { payload["quality"] = quality }
        if let duration { payload["duration"] = duration }
        if let outputDir { payload["output_dir"] = outputDir }
        _ = try await sendDict(req("PUT", "/api/sources/\(id)", json: payload))
    }

    func deleteSource(_ id: String) async throws {
        _ = try await sendDict(req("DELETE", "/api/sources/\(id)"))
    }

    func checkNow(_ id: String) async throws {
        _ = try await sendDict(req("POST", "/api/sources/\(id)/check"))
    }

    func startNow(_ id: String) async throws {
        _ = try await sendDict(req("POST", "/api/sources/\(id)/start-now"))
    }

    func monitorLog(_ id: String) async throws -> [String] {
        let d = try await sendDict(req("GET", "/api/sources/\(id)/log", query: ["lines": "120"]))
        if let lines = d["lines"] as? [String] { return lines }
        if let log = d["log"] as? [String] { return log }
        if let text = d["log"] as? String { return text.components(separatedBy: "\n") }
        return []
    }

    // ---- recordings ----

    func active() async throws -> [TikRecording] {
        struct Resp: Decodable { let recordings: [TikRecording] }
        return (try? await send(Resp.self, req("GET", "/api/recordings/active")).recordings) ?? []
    }

    func history() async throws -> [TikRecording] {
        struct Resp: Decodable { let history: [TikRecording] }
        return (try? await send(Resp.self, req("GET", "/api/recordings/history")).history) ?? []
    }

    func stopRecording(_ id: String) async throws {
        _ = try await sendDict(req("POST", "/api/recordings/\(id)/stop"))
    }

    func deleteRecording(_ id: String) async throws {
        _ = try await sendDict(req("DELETE", "/api/recordings/\(id)"))
    }

    func channelLog(platform: String, user: String) async throws -> [String] {
        let d = try await sendDict(req("GET", "/api/logs/\(platform)/\(user)", query: ["lines": "120"]))
        return (d["lines"] as? [String]) ?? []
    }

    // ---- settings ----

    func getSettings() async throws -> TikSettingsData {
        struct Resp: Decodable { let settings: TikSettingsData }
        return try await send(Resp.self, req("GET", "/api/settings")).settings
    }

    func saveSettings(_ s: TikSettingsData) async throws {
        var payload: [String: Any] = [
            "output_dir": s.outputDir,
            "default_quality": s.defaultQuality,
            "proxy": s.proxy,
            "default_interval": s.defaultInterval,
            "auto_convert": s.autoConvert,
        ]
        if let d = s.defaultDuration { payload["default_duration"] = d }
        _ = try await sendDict(req("PUT", "/api/settings", json: payload))
    }

    // ---- integrations (cookies + telegram) ----

    struct TikCookies: Decodable {
        var sessionid: String
        var ttTargetIdc: String
        var hasCookies: Bool

        enum CodingKeys: String, CodingKey {
            case sessionid = "sessionid_ss"
            case ttTargetIdc = "tt-target-idc"
            case hasCookies = "has_cookies"
        }
    }

    struct TikTelegram: Decodable {
        var apiId: String
        var apiHash: String
        var chatId: String
        var hasTelegram: Bool

        enum CodingKeys: String, CodingKey {
            case apiId = "api_id"
            case apiHash = "api_hash"
            case chatId = "chat_id"
            case hasTelegram = "has_telegram"
        }
    }

    func getIntegrations() async throws -> (cookies: TikCookies, telegram: TikTelegram) {
        struct Resp: Decodable {
            let cookies: TikCookies
            let telegram: TikTelegram
        }
        // Tolerate missing keys with safe defaults.
        let d = try await sendDict(req("GET", "/api/settings"))
        let dec = JSONDecoder()
        let cData = (try? JSONSerialization.data(withJSONObject: d["cookies"] ?? [:])) ?? Data()
        let tData = (try? JSONSerialization.data(withJSONObject: d["telegram"] ?? [:])) ?? Data()
        let cookies = (try? dec.decode(TikCookies.self, from: cData)) ?? TikCookies(sessionid: "", ttTargetIdc: "useast2a", hasCookies: false)
        let telegram = (try? dec.decode(TikTelegram.self, from: tData)) ?? TikTelegram(apiId: "", apiHash: "", chatId: "me", hasTelegram: false)
        return (cookies, telegram)
    }

    func saveCookies(sessionid: String, ttTargetIdc: String) async throws {
        _ = try await sendDict(req("PUT", "/api/settings/cookies", json: [
            "sessionid_ss": sessionid,
            "tt-target-idc": ttTargetIdc,
        ]))
    }

    func saveTelegram(apiId: String, apiHash: String, chatId: String) async throws {
        _ = try await sendDict(req("PUT", "/api/settings/telegram", json: [
            "api_id": apiId, "api_hash": apiHash, "chat_id": chatId,
        ]))
    }

    // ---- admin (restart / version, X-Admin-Key when configured) ----

    /// Returns the admin key, or nil when the server has none configured.
    func adminKey() async throws -> String? {
        let (data, resp) = try await session.data(for: req("GET", "/admin/admin-key"))
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { return nil }
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return obj?["admin_key"] as? String
    }

    private func adminReq(_ method: String, _ path: String, key: String?) -> URLRequest {
        var r = req(method, path)
        if let key { r.setValue(key, forHTTPHeaderField: "X-Admin-Key") }
        return r
    }

    func serverVersion(key: String?) async throws -> (current: String, latest: String) {
        struct Resp: Decodable {
            let current: String
            let latest: String
        }
        do {
            let v: Resp = try await send(Resp.self, adminReq("GET", "/admin/version", key: key))
            return (v.current, v.latest)
        } catch {
            return ("?", "?")
        }
    }

    func restartServer(key: String?) async throws {
        _ = try await sendDict(adminReq("POST", "/admin/restart", key: key))
    }
}
