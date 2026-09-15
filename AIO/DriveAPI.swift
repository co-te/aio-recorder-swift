//
//  DriveAPI.swift
//  TeleDrive
//
//  Typed client for the Tele-Drive FastAPI backend (/home/cote/tele-drive).
//  Auth: Bearer token header on every route. Errors arrive as
//  {"error": "..."} with non-2xx status.
//

import Foundation

// MARK: - Models (shapes verified against app/tg.py, upload_queue.py, eventlog.py, main.py)

struct TDFolder: Identifiable, Decodable {
    let peerType: String
    let peerId: Int
    let name: String
    let kind: String

    var id: String { "\(peerType)-\(peerId)" }

    enum CodingKeys: String, CodingKey {
        case peerType = "peer_type"
        case peerId = "peer_id"
        case name, kind
    }
}

struct TDFile: Identifiable, Decodable {
    let id: Int
    let name: String
    let size: Int
    let date: Int
    let type: String
    let mime: String
    let hasThumb: Bool
    let favorite: Bool
    let pinned: Bool
    let offline: Bool
    let group: String?

    /// Peer context is NOT in the item JSON — stamped post-decode by files().
    var peerType: String = "self"
    var peerId: Int = 0

    var rowId: String { "\(peerType)-\(peerId)-\(id)" }

    enum CodingKeys: String, CodingKey {
        case id, name, size, date, type, mime, favorite, pinned, offline, group
        case hasThumb = "has_thumb"
    }

    var isMedia: Bool { type == "video" || type == "audio" || type == "image" }
}

struct TDUploadJob: Identifiable, Decodable {
    let id: String
    let name: String
    let peerType: String
    let peerId: Int
    let status: String
    let done: Int
    let total: Int
    let error: String
    let batchId: String

    enum CodingKeys: String, CodingKey {
        case id, name, status, done, total, error
        case peerType = "peer_type"
        case peerId = "peer_id"
        case batchId = "batch_id"
    }

    var isActive: Bool { status == "pending" || status == "uploading" || status == "paused" }
    var fraction: Double { total <= 0 ? 0 : min(1, Double(done) / Double(total)) }
}

struct TDLogEntry: Identifiable, Decodable {
    /// Server sends time.time() float — decode tolerant.
    let time: Double
    let level: String
    let message: String

    var id: String { "\(time)-\(message.prefix(24))" }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let d = try? c.decode(Double.self, forKey: .time) {
            time = d
        } else if let i = try? c.decode(Int.self, forKey: .time) {
            time = Double(i)
        } else {
            time = 0
        }
        level = (try? c.decode(String.self, forKey: .level)) ?? "info"
        message = (try? c.decode(String.self, forKey: .message)) ?? ""
    }

    enum CodingKeys: String, CodingKey {
        case time, level, message
    }
}

struct TDUsage: Decodable {
    let date: String
    let uploadedBytes: Int
    let limitBytes: Int
    let remainingBytes: Int

    enum CodingKeys: String, CodingKey {
        case date
        case uploadedBytes = "uploaded_bytes"
        case limitBytes = "limit_bytes"
        case remainingBytes = "remaining_bytes"
    }

    var fractionUsed: Double {
        limitBytes <= 0 ? 0 : min(1, Double(uploadedBytes) / Double(limitBytes))
    }
}

struct TDLocalEntry: Identifiable, Decodable {
    let name: String
    let path: String
    let isDir: Bool
    let size: Int

    var id: String { path }

    enum CodingKeys: String, CodingKey {
        case name, path, size
        case isDir = "is_dir"
    }
}

// APIError lives in Shared.swift (single definition for all clients).

// MARK: - Settings (persisted on-device)

struct DriveSettings: Equatable {
    var host: String
    var port: Int
    var token: String

    static let defaults = DriveSettings(host: "192.168.110.58", port: 8001, token: "")

    var baseURL: String { "http://\(host):\(port)" }

    static let hostKey = "td_host"
    static let portKey = "td_port"
    static let tokenKey = "td_token"

    static func load() -> DriveSettings {
        let d = UserDefaults.standard
        return DriveSettings(
            host: d.string(forKey: hostKey) ?? defaults.host,
            port: d.object(forKey: portKey) as? Int ?? defaults.port,
            token: d.string(forKey: tokenKey) ?? ""
        )
    }

    func save() {
        let d = UserDefaults.standard
        d.set(host, forKey: Self.hostKey)
        d.set(port, forKey: Self.portKey)
        d.set(token, forKey: Self.tokenKey)
    }
}

// MARK: - API

final class DriveAPI {
    let settings: DriveSettings
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(settings: DriveSettings) {
        self.settings = settings
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15
        session = URLSession(configuration: cfg)
    }

    private var bearer: [String: String] {
        var h = [String: String]()
        if !settings.token.isEmpty { h["Authorization"] = "Bearer \(settings.token)" }
        return h
    }

    private func url(_ path: String, _ query: [String: String] = [:]) -> URL {
        var comps = URLComponents(string: settings.baseURL + path)!
        if !query.isEmpty {
            comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        return comps.url!
    }

    /// Form-encoded POST (what the backend's Form(...) params expect).
    private func formRequest(_ path: String, _ fields: [String: String] = [:]) -> URLRequest {
        var req = URLRequest(url: url(path))
        req.httpMethod = "POST"
        req.allHTTPHeaderFields = bearer.merging(
            ["Content-Type": "application/x-www-form-urlencoded; charset=utf-8"]
        ) { _, new in new }
        req.httpBody = fields
            .map { "\($0.key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        return req
    }

    private func getRequest(_ path: String, query: [String: String] = [:]) -> URLRequest {
        var req = URLRequest(url: url(path, query))
        req.httpMethod = "GET"
        req.allHTTPHeaderFields = bearer
        return req
    }

    private func decodeDict(_ data: Data, status: Int) throws -> [String: Any] {
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(status) else {
            throw APIError(statusCode: status, message: (obj["error"] as? String) ?? "")
        }
        return obj
    }

    private func sendDict(_ req: URLRequest) async throws -> [String: Any] {
        let (data, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        return try decodeDict(data, status: code)
    }

    private func send<T: Decodable>(_ type: T.Type, _ req: URLRequest) async throws -> T {
        let (data, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw APIError(statusCode: code, message: (obj?["error"] as? String) ?? "")
        }
        do {
            return try decoder.decode(type, from: data)
        } catch let e as DecodingError {
            throw APIError(statusCode: 200, message: "Bad response shape: \(e)")
        }
    }

    // ---- auth / status ----

    struct StatusResp: Decodable {
        let authenticated: Bool
    }

    func checkAuth() async throws -> Bool {
        let r: StatusResp = try await send(StatusResp.self, getRequest("/api/status"))
        return r.authenticated
    }

    func login(token: String) async throws {
        _ = try await sendDict(formRequest("/api/auth", ["token": token]))
    }

    func logout() async throws {
        _ = try await sendDict(formRequest("/api/logout"))
    }

    func sync() async throws {
        _ = try await sendDict(formRequest("/api/sync"))
    }

    // ---- folders / files ----

    func folders() async throws -> [TDFolder] {
        struct Resp: Decodable { let folders: [TDFolder] }
        return try await send(Resp.self, getRequest("/api/folders")).folders
    }

    func createFolder(_ name: String) async throws {
        _ = try await sendDict(formRequest("/api/folders", ["name": name]))
    }

    /// Returns (items with peer stamped, nextOffset).
    func files(peerType: String, peerId: Int, offsetId: Int = 0, limit: Int = 50) async throws -> ([TDFile], Int) {
        struct Resp: Decodable {
            let items: [TDFile]
            let nextOffset: Int
            enum CodingKeys: String, CodingKey {
                case items
                case nextOffset = "next_offset"
            }
        }
        let r: Resp = try await send(Resp.self, getRequest("/api/files", query: [
            "peer_type": peerType,
            "peer_id": String(peerId),
            "offset_id": String(offsetId),
            "limit": String(limit),
        ]))
        let stamped = r.items.map { item -> TDFile in
            var m = item
            m.peerType = peerType
            m.peerId = peerId
            return m
        }
        return (stamped, r.nextOffset)
    }

    // ---- smart views ----

    func view(_ name: String, peerType: String = "self", peerId: Int = 0, group: String? = nil) async throws -> [TDFile] {
        struct Resp: Decodable { let items: [TDFile] }
        var q = ["peer_type": peerType, "peer_id": String(peerId)]
        if let group { q["group"] = group }
        let r: Resp = try await send(Resp.self, getRequest("/api/view/\(name)", query: q))
        return r.items.map { item -> TDFile in
            var m = item
            m.peerType = peerType
            m.peerId = peerId
            return m
        }
    }

    func groups() async throws -> [String] {
        struct Resp: Decodable { let groups: [String] }
        return (try? await send(Resp.self, getRequest("/api/groups")).groups) ?? []
    }

    func createGroup(_ name: String) async throws {
        _ = try await sendDict(formRequest("/api/groups", ["name": name]))
    }

    // ---- flags / groups / text / delete ----

    func toggleFlag(_ file: TDFile, flag: String, value: Bool) async throws {
        _ = try await sendDict(formRequest(
            "/api/file/\(file.peerType)/\(file.peerId)/\(file.id)/\(flag)",
            ["value": value ? "true" : "false"]
        ))
    }

    func assignGroup(_ file: TDFile, group: String?) async throws {
        var fields = [String: String]()
        if let group, !group.isEmpty { fields["group"] = group }
        _ = try await sendDict(formRequest(
            "/api/file/\(file.peerType)/\(file.peerId)/\(file.id)/group", fields))
    }

    func deleteFile(_ file: TDFile) async throws {
        _ = try await sendDict(formRequest("/api/delete/\(file.peerType)/\(file.peerId)/\(file.id)"))
    }

    func readText(_ file: TDFile) async throws -> String {
        let d = try await sendDict(getRequest("/api/text/\(file.peerType)/\(file.peerId)/\(file.id)"))
        return (d["content"] as? String) ?? ""
    }

    func writeText(_ file: TDFile, content: String) async throws {
        _ = try await sendDict(formRequest(
            "/api/text/\(file.peerType)/\(file.peerId)/\(file.id)", ["content": content]))
    }

    // ---- uploads ----

    func uploadJobs() async throws -> [TDUploadJob] {
        struct Resp: Decodable { let jobs: [TDUploadJob] }
        return (try? await send(Resp.self, getRequest("/api/uploads")).jobs) ?? []
    }

    func pauseJob(_ id: String) async throws {
        _ = try await sendDict(formRequest("/api/uploads/\(id)/pause"))
    }

    func resumeJob(_ id: String) async throws {
        _ = try await sendDict(formRequest("/api/uploads/\(id)/resume"))
    }

    func cancelJob(_ id: String) async throws {
        _ = try await sendDict(formRequest("/api/uploads/\(id)/cancel"))
    }

    func pauseAll() async throws {
        _ = try await sendDict(formRequest("/api/uploads/pause"))
    }

    func resumeAll() async throws {
        _ = try await sendDict(formRequest("/api/uploads/resume"))
    }

    func cancelAll() async throws {
        _ = try await sendDict(formRequest("/api/uploads/cancel"))
    }

    /// Multipart phone → Telegram upload.
    func uploadFile(data: Data, filename: String, mime: String,
                    peerType: String, peerId: Int) async throws {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        field("peer_type", peerType)
        field("peer_id", String(peerId))
        field("name", filename)
        field("upload_id", UUID().uuidString)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mime)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var req = URLRequest(url: url("/api/upload"))
        req.httpMethod = "POST"
        req.allHTTPHeaderFields = bearer.merging(
            ["Content-Type": "multipart/form-data; boundary=\(boundary)"]
        ) { _, new in new }
        req.httpBody = body
        req.timeoutInterval = 300
        _ = try await sendDict(req)
    }

    // ---- local drive (Pi) ----

    struct LocalListResp: Decodable {
        let root: String
        let path: String
        let entries: [TDLocalEntry]
    }

    func localList(path: String = "") async throws -> LocalListResp {
        try await send(LocalListResp.self, getRequest("/api/local/list", query: ["path": path]))
    }

    func localUpload(path: String, peerType: String, peerId: Int) async throws {
        _ = try await sendDict(formRequest("/api/local/upload", [
            "peer_type": peerType,
            "peer_id": String(peerId),
            "path": path,
            "upload_id": UUID().uuidString,
        ]))
    }

    // ---- usage / settings / logs ----

    func usage() async throws -> TDUsage {
        try await send(TDUsage.self, getRequest("/api/usage"))
    }

    func resetUsage() async throws {
        _ = try await sendDict(formRequest("/api/usage/reset"))
    }

    func maxConcurrent() async throws -> Int {
        let d = try await sendDict(getRequest("/api/settings"))
        return (d["max_concurrent_uploads"] as? Int) ?? 2
    }

    func saveMaxConcurrent(_ n: Int) async throws {
        _ = try await sendDict(formRequest("/api/settings", ["max_concurrent_uploads": String(n)]))
    }

    func logs() async throws -> [TDLogEntry] {
        struct Resp: Decodable { let entries: [TDLogEntry] }
        return (try? await send(Resp.self, getRequest("/api/logs")).entries) ?? []
    }

    // ---- authed media ----

    /// Raw bytes with auth (thumbs, downloads). AVPlayer/AsyncImage can't send headers.
    func authedData(path: String) async throws -> Data {
        var req = URLRequest(url: URL(string: settings.baseURL + path)!)
        req.allHTTPHeaderFields = bearer
        let (data, resp) = try await session.data(for: req)
        guard (200..<300).contains((resp as? HTTPURLResponse)?.statusCode ?? 0) else {
            throw APIError(statusCode: (resp as? HTTPURLResponse)?.statusCode ?? 0, message: "Media fetch failed")
        }
        return data
    }

    func thumbData(_ file: TDFile) async throws -> Data {
        try await authedData(path: "/api/thumb/\(file.peerType)/\(file.peerId)/\(file.id)")
    }

    /// Recording-archiver progress (status.json written by the Pi script).
    func archiverStatus() async throws -> ArchiverStatus {
        var comps = URLComponents(string: settings.baseURL + "/api/local/file")!
        comps.queryItems = [URLQueryItem(name: "path", value: "recording-archiver/status.json")]
        var req = URLRequest(url: comps.url!)
        req.allHTTPHeaderFields = bearer
        req.timeoutInterval = 15
        let (data, resp) = try await session.data(for: req)
        guard (200..<300).contains((resp as? HTTPURLResponse)?.statusCode ?? 0) else {
            throw APIError(statusCode: (resp as? HTTPURLResponse)?.statusCode ?? 0,
                           message: "Archiver status unavailable")
        }
        return try decoder.decode(ArchiverStatus.self, from: data)
    }

    /// Ask the Pi to run the archiver now (systemd path unit picks it up).
    func archiverRun() async throws -> String {
        var req = URLRequest(url: URL(string: settings.baseURL + "/api/archiver/run")!)
        req.httpMethod = "POST"
        req.allHTTPHeaderFields = bearer
        req.timeoutInterval = 15
        let (data, resp) = try await session.data(for: req)
        guard (200..<300).contains((resp as? HTTPURLResponse)?.statusCode ?? 0) else {
            throw APIError(statusCode: (resp as? HTTPURLResponse)?.statusCode ?? 0,
                           message: "Run request failed")
        }
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return (obj?["state"] as? String) ?? "requested"
    }

    func downloadToTemp(_ file: TDFile) async throws -> URL {
        let data = try await authedData(path: "/api/download/\(file.peerType)/\(file.peerId)/\(file.id)")
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent(file.name)
        try data.write(to: dest, options: .atomic)
        return dest
    }
}
