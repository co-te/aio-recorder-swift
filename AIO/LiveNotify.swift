//
//  LiveNotify.swift — background live-check + local notifications.
//  Polls tik/tango/miner while the app lives, fires a UNUserNotification
//  on each offline→live transition. No push server needed.
//

import Foundation
import UserNotifications

final class LiveMonitor: ObservableObject {
    private var tik: TikAPI?
    private var tango: TangoAPI?
    private var miner: MinerAPI?
    private var task: Task<Void, Never>?

    private var seenTik = Set<String>()
    private var seenTango = Set<String>()
    private var seenMiner = Set<String>()
    private var firstRun = true

    private let d = UserDefaults.standard

    var tikOn: Bool { d.object(forKey: "notify_tik") as? Bool ?? true }
    var tangoOn: Bool { d.object(forKey: "notify_tango") as? Bool ?? true }
    var minerOn: Bool { d.object(forKey: "notify_miner") as? Bool ?? true }
    var interval: TimeInterval {
        let v = d.object(forKey: "notify_interval") as? Int ?? 60
        return TimeInterval(min(300, max(30, v)))
    }

    static func requestAuth() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            return granted
        } catch {
            return false
        }
    }

    static func test() {
        fire(title: "Test notification", body: "Live alerts are working.")
    }

    func configure(tik: TikAPI, tango: TangoAPI, miner: MinerAPI) {
        self.tik = tik
        self.tango = tango
        self.miner = miner
    }

    func start() {
        stop()
        task = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.pollOnce()
                try? await Task.sleep(nanoseconds: UInt64(self.interval * 1_000_000_000))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    func pollOnce() async {
        if tikOn { await pollTik() }
        if tangoOn { await pollTango() }
        if minerOn { await pollMiner() }
        firstRun = false
    }

    // MARK: - Tik (TikTok + Twitch via :8090)

    private func pollTik() async {
        guard let tik else { return }
        var live = Set<String>()
        if let srcs = try? await tik.sources() {
            for s in srcs where s.currentlyLive {
                live.insert("\(s.platform):\(s.user)")
            }
        }
        if let act = try? await tik.active() {
            for r in act where r.isActive {
                live.insert("\(r.platform):\(r.user)")
            }
        }
        if firstRun {
            seenTik = live
            return
        }
        for key in live.subtracting(seenTik) {
            let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
            let plat = parts.first ?? "tik"
            let user = parts.count > 1 ? parts[1] : key
            let label = plat == "twitch" ? "Twitch" : "TikTok"
            Self.fire(title: "\(user) is LIVE (\(label))", body: "Tap Tik tab to watch / recording started.")
        }
        seenTik = live
    }

    // MARK: - Tango (:8091)

    private func pollTango() async {
        guard let tango else { return }
        guard let list = try? await tango.streamers() else { return }
        let live = Set(list.filter { $0.isLive }.map { $0.handle })
        if firstRun {
            seenTango = live
            return
        }
        for h in live.subtracting(seenTango) {
            Self.fire(title: "\(h) is LIVE (Tango)", body: "Recording started — see Tango tab.")
        }
        seenTango = live
    }

    // MARK: - Miner (:8000, always notify, embed miner state)

    private func pollMiner() async {
        guard let miner else { return }
        async let runTask = miner.minerStatus()
        async let listTask = miner.streamers()
        guard let list = try? await listTask else { return }
        let running = (try? await runTask) ?? false
        let live = Set(list.filter { $0.isOnline }.map { $0.username })
        if firstRun {
            seenMiner = live
            return
        }
        for u in live.subtracting(seenMiner) {
            let title: String? = list.first(where: { $0.username == u })?.stream?.title
            let state = running ? "miner running" : "miner OFFLINE"
            var body = state
            if let title, !title.isEmpty { body += " — \(title)" }
            Self.fire(title: "\(u) is LIVE (Twitch)", body: body)
        }
        seenMiner = live
    }

    // MARK: - fire

    private static func fire(title: String, body: String) {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        let req = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: c,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        UNUserNotificationCenter.current().add(req)
        NotificationCenter.default.post(name: .minerToast, object: "\(title) — \(body)")
    }
}
