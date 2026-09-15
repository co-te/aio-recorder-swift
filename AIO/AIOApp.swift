//
//  AIOApp.swift — shell, service tabs, 4-backend settings, connect flow.
//

import SwiftUI

extension Notification.Name {
    static let minerToast = Notification.Name("minerToast")
    static let driveToast = Notification.Name("driveToast")
}

// MARK: - All four backends in one settings bag

struct AIOSettings: Equatable {
    var tik: TikSettings
    var tango: TangoSettings
    var miner: MinerSettings
    var drive: DriveSettings

    static func load() -> AIOSettings {
        AIOSettings(tik: .load(), tango: .load(), miner: .load(), drive: .load())
    }

    func save() {
        tik.save()
        tango.save()
        miner.save()
        drive.save()
    }

    var hasAnyHost: Bool {
        !tik.host.isEmpty || !tango.host.isEmpty || !miner.host.isEmpty || !drive.host.isEmpty
    }
}

@main
struct AIOApp: App {
    @State private var settings: AIOSettings
    @State private var connected: Bool

    init() {
        Theme.apply()
        let s = AIOSettings.load()
        _settings = State(initialValue: s)
        _connected = State(initialValue: s.hasAnyHost)
    }

    var body: some Scene {
        WindowGroup {
            if connected {
                AIOShell(settings: $settings)
            } else {
                AIOConnectScreen { s in
                    settings = s
                    connected = true
                }
            }
        }
    }
}

// MARK: - Shell

struct AIOShell: View {
    @Binding var settings: AIOSettings

    @State private var tikAPI: TikAPI
    @State private var tangoAPI: TangoAPI
    @State private var minerAPI: MinerAPI
    @State private var driveAPI: DriveAPI
    @State private var tab = 0
    @State private var toast: String?

    init(settings: Binding<AIOSettings>) {
        _settings = settings
        let s = settings.wrappedValue
        _tikAPI = State(initialValue: TikAPI(settings: s.tik))
        _tangoAPI = State(initialValue: TangoAPI(settings: s.tango))
        _minerAPI = State(initialValue: MinerAPI(settings: s.miner))
        _driveAPI = State(initialValue: DriveAPI(settings: s.drive))
    }

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { TikRootView(api: tikAPI) }
                .tabItem { Label("Tik", systemImage: "video.fill") }.tag(0)
            NavigationStack { TangoRootView(api: tangoAPI) }
                .tabItem { Label("Tango", systemImage: "phone.fill") }.tag(1)
            NavigationStack { MinerRootView(api: minerAPI) }
                .tabItem { Label("Miner", systemImage: "diamond.fill") }.tag(2)
            NavigationStack { DriveRootView(api: driveAPI) }
                .tabItem { Label("Drive", systemImage: "externaldrive.fill") }.tag(3)
            NavigationStack {
                AIOSettingsView(settings: $settings) { updated in
                    settings = updated
                    tikAPI = TikAPI(settings: updated.tik)
                    tangoAPI = TangoAPI(settings: updated.tango)
                    minerAPI = MinerAPI(settings: updated.miner)
                    driveAPI = DriveAPI(settings: updated.drive)
                }
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }.tag(4)
        }
        .tint(Theme.blue)
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(.subheadline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.bottom, 90)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .minerToast)) { note in
            showToast(note.object as? String ?? "Done")
        }
        .onReceive(NotificationCenter.default.publisher(for: .driveToast)) { note in
            showToast(note.object as? String ?? "Done")
        }
    }

    private func showToast(_ msg: String) {
        withAnimation { toast = msg }
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run { withAnimation { toast = nil } }
        }
    }
}

// MARK: - Sub-tabs for miner + drive (keeps the tab bar at 5 items)

struct MinerRootView: View {
    let api: MinerAPI
    @State private var section = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $section) {
                Text("Miner").tag(0)
                Text("Channels").tag(1)
                Text("Logs").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            switch section {
            case 0: DashboardView(api: api)
            case 1: ChannelsView(api: api)
            default: LogsView(api: api)
            }
        }
        .background(AppBackground())
        .navigationTitle("Points miner")
    }
}

struct DriveRootView: View {
    let api: DriveAPI
    @State private var section = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $section) {
                Text("Files").tag(0)
                Text("Views").tag(1)
                Text("Uploads").tag(2)
                Text("Local").tag(3)
                Text("Logs").tag(4)
                Text("Archiver").tag(5)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            switch section {
            case 0: FilesView(api: api)
            case 1: ViewsView(api: api)
            case 2: UploadsView(api: api)
            case 3: LocalView(api: api)
            case 5: ArchiverView(api: api)
            default: DriveLogsView(api: api)
            }
        }
        .background(AppBackground())
        .navigationTitle("Tele-Drive")
    }
}

// MARK: - Settings (all four backends)

struct AIOSettingsView: View {
    @Binding var settings: AIOSettings
    let onApplied: (AIOSettings) -> Void

    @State private var tikHost = ""
    @State private var tikPort = ""
    @State private var tangoHost = ""
    @State private var tangoPort = ""
    @State private var minerHost = ""
    @State private var minerPort = ""
    @State private var minerToken = ""
    @State private var driveHost = ""
    @State private var drivePort = ""
    @State private var driveToken = ""
    @State private var testing = false
    @State private var testLines: [String] = []
    @State private var driveUsage: TDUsage?
    @State private var maxConc = 2
    @State private var driveNote: String?
    @State private var confirmLogout = false

    private var driveAPI: DriveAPI { DriveAPI(settings: current().drive) }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        CardHeader(title: "Tik recorder", icon: "video.fill")
                        GlassField(icon: "wifi", placeholder: "Pi IP", text: $tikHost, keyboard: .decimalPad)
                        GlassField(icon: "number", placeholder: "Port (8090)", text: $tikPort, keyboard: .numberPad)
                    }
                }
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        CardHeader(title: "Tango recorder", icon: "phone.fill")
                        GlassField(icon: "wifi", placeholder: "Pi IP", text: $tangoHost, keyboard: .decimalPad)
                        GlassField(icon: "number", placeholder: "Port (8091)", text: $tangoPort, keyboard: .numberPad)
                    }
                }
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        CardHeader(title: "Points miner", icon: "diamond.fill")
                        GlassField(icon: "wifi", placeholder: "Pi IP", text: $minerHost, keyboard: .decimalPad)
                        GlassField(icon: "number", placeholder: "Port (8000)", text: $minerPort, keyboard: .numberPad)
                        GlassField(icon: "key.fill", placeholder: "TTV_API_TOKEN", text: $minerToken, secure: true)
                    }
                }
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        CardHeader(title: "Tele-Drive", icon: "externaldrive.fill")
                        GlassField(icon: "wifi", placeholder: "Pi IP", text: $driveHost, keyboard: .decimalPad)
                        GlassField(icon: "number", placeholder: "Port (8001)", text: $drivePort, keyboard: .numberPad)
                        GlassField(icon: "key.fill", placeholder: "API token", text: $driveToken, secure: true)
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        CardHeader(title: "Connections", icon: "bolt.horizontal")
                        HStack {
                            GlassButton(title: "Test all", icon: "dot.radiowaves.left.and.right", tint: Theme.blue) {
                                Task { await testAll() }
                            }
                            .disabled(testing)
                            if testing { ProgressView().tint(.white) }
                            Spacer()
                        }
                        ForEach(testLines, id: \.self) { line in
                            Text(line).font(.caption2).foregroundStyle(Theme.textSecondary)
                        }
                    }
                }

                if let driveUsage {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            CardHeader(title: "Drive daily quota", icon: "gauge.with.dots.needle.67percent")
                            ProgressView(value: driveUsage.fractionUsed)
                                .tint(driveUsage.fractionUsed > 0.9 ? Theme.red : Theme.blue)
                            SecondaryLabel(
                                "\(Fmt.bytes(driveUsage.uploadedBytes)) of \(Fmt.bytes(driveUsage.limitBytes)) used · \(Fmt.bytes(driveUsage.remainingBytes)) left",
                                font: .caption)
                            HStack {
                                GlassButton(title: "Reset", icon: "arrow.counterclockwise", tint: Theme.warn) {
                                    Task {
                                        try? await driveAPI.resetUsage()
                                        await loadDrive()
                                    }
                                }
                                Spacer()
                            }
                        }
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        CardHeader(title: "Drive uploads", icon: "cloud.upload")
                        Stepper("Max concurrent: \(maxConc)", value: $maxConc, in: 1...8)
                            .foregroundStyle(Theme.textPrimary)
                            .onChange(of: maxConc) { n in
                                Task { try? await driveAPI.saveMaxConcurrent(n) }
                            }
                        HStack(spacing: 10) {
                            GlassButton(title: "Sync", icon: "arrow.triangle.2.circlepath", tint: Theme.green) {
                                Task {
                                    try? await driveAPI.sync()
                                    driveNote = "Sync requested."
                                }
                            }
                            GlassButton(title: "Logout", icon: "rectangle.portrait.and.arrow.right", tint: Theme.red) {
                                confirmLogout = true
                            }
                        }
                        if let driveNote {
                            SecondaryLabel(driveNote, font: .caption)
                        }
                    }
                }
                .confirmationDialog("Log out of Telegram on the server?", isPresented: $confirmLogout) {
                    Button("Logout", role: .destructive) {
                        Task { try? await driveAPI.logout() }
                    }
                }

                GlassButton(title: "Save", icon: "checkmark", tint: Theme.blue, prominent: true) {
                    apply()
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(AppBackground())
        .navigationTitle("Settings")
        .onAppear { fill() }
        .task { await loadDrive() }
    }

    private func loadDrive() async {
        driveUsage = try? await driveAPI.usage()
        if let n = try? await driveAPI.maxConcurrent() { maxConc = n }
    }

    private func fill() {
        tikHost = settings.tik.host
        tikPort = String(settings.tik.port)
        tangoHost = settings.tango.host
        tangoPort = String(settings.tango.port)
        minerHost = settings.miner.host
        minerPort = String(settings.miner.port)
        minerToken = settings.miner.token
        driveHost = settings.drive.host
        drivePort = String(settings.drive.port)
        driveToken = settings.drive.token
    }

    private func current() -> AIOSettings {
        AIOSettings(
            tik: TikSettings(
                host: tikHost.trimmingCharacters(in: .whitespaces).isEmpty ? settings.tik.host : tikHost.trimmingCharacters(in: .whitespaces),
                port: Int(tikPort) ?? settings.tik.port),
            tango: TangoSettings(
                host: tangoHost.trimmingCharacters(in: .whitespaces).isEmpty ? settings.tango.host : tangoHost.trimmingCharacters(in: .whitespaces),
                port: Int(tangoPort) ?? settings.tango.port),
            miner: MinerSettings(
                host: minerHost.trimmingCharacters(in: .whitespaces).isEmpty ? settings.miner.host : minerHost.trimmingCharacters(in: .whitespaces),
                port: Int(minerPort) ?? settings.miner.port,
                token: minerToken,
                refreshSeconds: settings.miner.refreshSeconds),
            drive: DriveSettings(
                host: driveHost.trimmingCharacters(in: .whitespaces).isEmpty ? settings.drive.host : driveHost.trimmingCharacters(in: .whitespaces),
                port: Int(drivePort) ?? settings.drive.port,
                token: driveToken))
    }

    private func testAll() async {
        testing = true
        defer { testing = false }
        let c = current()
        var lines: [String] = []
        do {
            _ = try await TikAPI(settings: c.tik).sources()
            lines.append("Tik: reachable")
        } catch { lines.append("Tik: \(error.messageText)") }
        do {
            _ = try await TangoAPI(settings: c.tango).streamers()
            lines.append("Tango: reachable")
        } catch { lines.append("Tango: \(error.messageText)") }
        do {
            let running = try await MinerAPI(settings: c.miner).minerStatus()
            lines.append(running ? "Miner: authenticated + running" : "Miner: authenticated, process offline")
        } catch { lines.append("Miner: \(error.messageText)") }
        do {
            let ok = try await DriveAPI(settings: c.drive).checkAuth()
            lines.append(ok ? "Drive: authenticated" : "Drive: token rejected")
        } catch { lines.append("Drive: \(error.messageText)") }
        testLines = lines
    }

    private func apply() {
        let s = current()
        s.save()
        onApplied(s)
    }
}

// MARK: - Connect

struct AIOConnectScreen: View {
    let onConnect: (AIOSettings) -> Void

    @State private var host = "192.168.110.58"
    @State private var minerToken = ""
    @State private var driveToken = ""
    @State private var busy = false
    @State private var err: String?

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 10) {
                        Image(systemName: "square.stack.3d.up.fill")
                            .font(.system(size: 50))
                            .foregroundStyle(Theme.blue)
                        Text("AIO Recorder")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)
                        SecondaryLabel("Tik · Tango · Miner · Drive — one app.")
                    }
                    .padding(.top, 60)

                    GlassCard {
                        VStack(spacing: 12) {
                            GlassField(icon: "wifi", placeholder: "Pi IP address", text: $host, keyboard: .decimalPad)
                            GlassField(icon: "key.fill", placeholder: "Miner token (TTV_API_TOKEN)", text: $minerToken, secure: true)
                            GlassField(icon: "key.fill", placeholder: "Drive token", text: $driveToken, secure: true)
                            if let err {
                                Label(err, systemImage: "xmark.octagon.fill")
                                    .font(.caption)
                                    .foregroundStyle(Theme.red)
                            }
                        }
                        .padding(4)
                    }
                    GlassButton(title: busy ? "Connecting…" : "Connect",
                                icon: "link", tint: Theme.blue, prominent: true) {
                        Task { await connect() }
                    }
                    .disabled(busy)
                    .frame(maxWidth: .infinity)
                    SecondaryLabel("Tik :8090 + Tango :8091 need no token.", font: .caption2)
                }
                .padding(20)
            }
        }
    }

    private func connect() async {
        busy = true
        defer { busy = false }
        let h = host.trimmingCharacters(in: .whitespaces)
        let s = AIOSettings(
            tik: TikSettings(host: h, port: 8090),
            tango: TangoSettings(host: h, port: 8091),
            miner: MinerSettings(host: h, port: 8000, token: minerToken, refreshSeconds: 10),
            drive: DriveSettings(host: h, port: 8001, token: driveToken))
        // Verify at least one backend answers before entering.
        var ok = false
        if (try? await TikAPI(settings: s.tik).sources()) != nil { ok = true }
        if (try? await TangoAPI(settings: s.tango).streamers()) != nil { ok = true }
        if (try? await MinerAPI(settings: s.miner).minerStatus()) != nil { ok = true }
        if (try? await DriveAPI(settings: s.drive).checkAuth()) == true { ok = true }
        guard ok else {
            err = "No backend answered at \(h) — check the IP."
            return
        }
        s.save()
        onConnect(s)
    }
}
