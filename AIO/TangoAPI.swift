//
//  TangoAPI.swift
//  AIO — client for the Tango.me recorder (Flask, :8091, no auth).
//  Shapes verified live against /api/streamers, /api/status, /api/recordings.
//

import Foundation

// MARK: - Models

struct TangoStreamer: Identifiable, Decodable {
    let handle: String
    let status: String
    let segments: Int
    let seconds: Int
    let file: String

    var id: String { handle }

    var isRecording: Bool { status == "recording" || status == "starting" }
    var isLive: Bool { isRecording || status == "live" }
}

struct TangoRecording: Identifiable, Decodable {
    let name: String
    let size: Int
    let mtime: Int

    var id: String { name }
}

// MARK: - Connection settings

struct TangoSettings: Equatable {
    var host: String
    var port: Int

    static let defaults = TangoSettings(host: "192.168.110.58", port: 8091)
    var baseURL: String { "http://\(host):\(port)" }

    static let hostKey = "tango_host"
    static let portKey = "tango_port"

    static func load() -> TangoSettings {
        let d = UserDefaults.standard
        return TangoSettings(
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

final class TangoAPI {
    let settings: TangoSettings
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(settings: TangoSettings) {
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
            throw APIError(statusCode: code, message: "HTTP \(code)")
        }
        // Flask sometimes returns {ok:false} with 200 — surface it.
        if let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let ok = obj["ok"] as? Bool, !ok {
            throw APIError(statusCode: code, message: (obj["error"] as? String) ?? "Request failed")
        }
        do {
            return try decoder.decode(type, from: data)
        } catch let e as DecodingError {
            throw APIError(statusCode: 200, message: "Bad response shape: \(e)")
        }
    }

    private func sendOK(_ r: URLRequest) async throws {
        struct OkResp: Decodable {
            let ok: Bool?
            let error: String?
        }
        let o: OkResp = try await send(OkResp.self, r)
        if let ok = o.ok, !ok {
            throw APIError(statusCode: 200, message: o.error ?? "Request failed")
        }
    }

    // ---- watchlist ----

    func streamers() async throws -> [TangoStreamer] {
        try await send([TangoStreamer].self, req("GET", "/api/streamers"))
    }

    func addStreamer(_ handle: String) async throws {
        try await sendOK(req("POST", "/api/streamers", json: ["handle": handle]))
    }

    func removeStreamer(_ handle: String) async throws {
        try await sendOK(req("DELETE", "/api/streamers", json: ["handle": handle]))
    }

    // ---- record control ----

    func record(_ handle: String, seconds: Int = 0) async throws {
        try await sendOK(req("POST", "/api/record", json: ["handle": handle, "seconds": seconds]))
    }

    func stop(_ handle: String) async throws {
        try await sendOK(req("POST", "/api/stop", json: ["handle": handle]))
    }

    /// Poll watchlist: starts recording any live streamer. Returns statuses.
    func check() async throws -> [String: String] {
        struct Resp: Decodable {
            let started: [String]
            let statuses: [String: String]
        }
        return try await send(Resp.self, req("POST", "/api/check", json: [:])).statuses
    }

    func status() async throws -> [String: String] {
        struct Full: Decodable {
            let status: String?
        }
        let d = try await send([String: Full].self, req("GET", "/api/status"))
        return Dictionary(uniqueKeysWithValues: d.map { ($0.key, $0.value.status ?? "idle") })
    }

    func log(handle: String) async throws -> [String] {
        // /api/log returns a bare JSON array of lines.
        (try? await send([String].self, req("GET", "/api/log", query: ["handle": handle]))) ?? []
    }

    // ---- recordings ----

    func recordings() async throws -> [TangoRecording] {
        (try? await send([TangoRecording].self, req("GET", "/api/recordings"))) ?? []
    }

    func downloadToTemp(_ rec: TangoRecording) async throws -> URL {
        var r = URLRequest(url: url("/api/dl", ["name": rec.name]))
        r.timeoutInterval = 300
        let (data, resp) = try await session.data(for: r)
        guard (200..<300).contains((resp as? HTTPURLResponse)?.statusCode ?? 0) else {
            throw APIError(statusCode: (resp as? HTTPURLResponse)?.statusCode ?? 0, message: "Download failed")
        }
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent(rec.name)
        try data.write(to: dest, options: .atomic)
        return dest
    }

    func thumbData(_ rec: TangoRecording) async throws -> Data {
        let (data, resp) = try await session.data(for: req("GET", "/api/thumb", query: ["name": rec.name]))
        guard (200..<300).contains((resp as? HTTPURLResponse)?.statusCode ?? 0) else {
            throw APIError(statusCode: 0, message: "No thumbnail")
        }
        return data
    }
}
