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
    var strip: StripSettings
    var miner: MinerSettings
    var drive: DriveSettings

    static func load() -> AIOSettings {
        AIOSettings(tik: .load(), tango: .load(), strip: .load(),
                    miner: .load(), drive: .load())
    }

    func save() {
        tik.save()
        tango.save()
        strip.save()
        miner.save()
        drive.save()
    }

    var hasAnyHost: Bool {
        !tik.host.isEmpty || !tango.host.isEmpty || !strip.host.isEmpty
            || !miner.host.isEmpty || !drive.host.isEmpty
    }
}

@main
struct AIOApp: App {
    @State private var settings: AIOSettings
    @State private var connected: Bool
    @ObservedObject private var security = SecurityManager.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        Theme.apply()
        let s = AIOSettings.load()
        _settings = State(initialValue: s)
        _connected = State(initialValue: s.hasAnyHost)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if connected {
                    if security.isBiometricEnabled && !security.isUnlocked {
                        VStack(spacing: 20) {
                            Image(systemName: "lock.shield.fill")
                                .font(.system(size: 64))
                                .foregroundStyle(Theme.blue)
                            Text("AIO Controller Locked")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundStyle(Theme.textPrimary)
                            Text("Authenticate to access stream recorders and drive.")
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                                .multilineTextAlignment(.center)
                            GlassButton(title: "Unlock with Face ID", icon: "faceid", tint: Theme.blue, prominent: true) {
                                security.authenticate { _ in }
                            }
                        }
                        .padding(32)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(AppBackground())
                        .onAppear {
                            security.authenticate { _ in }
                        }
                    } else {
                        AIOShell(settings: $settings)
                    }
                } else {
                    AIOConnectScreen { s in
                        settings = s
                        connected = true
                    }
                }
            }
            .overlay {
                if scenePhase != .active && security.isPrivacyBlurEnabled {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .ignoresSafeArea()
                        .overlay {
                            VStack(spacing: 12) {
                                Image(systemName: "lock.shield.fill")
                                    .font(.system(size: 44))
                                    .foregroundStyle(Theme.blue)
                                Text("AIO Controller")
                                    .font(.headline)
                                    .foregroundStyle(Theme.textPrimary)
                            }
                        }
                }
            }
            .onChange(of: scenePhase) { phase in
                if phase == .background && security.isBiometricEnabled {
                    security.isUnlocked = false
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
    @State private var stripAPI: StripAPI
    @State private var minerAPI: MinerAPI
    @State private var driveAPI: DriveAPI
    @State private var tab = 0
    @State private var recorderSection = 0
    @State private var minerSection = 0
    @State private var driveSection = 0
    @State private var driveUploadCount = 0
    @State private var toast: String?
    @State private var toastTask: Task<Void, Never>?

    init(settings: Binding<AIOSettings>) {
        _settings = settings
        let s = settings.wrappedValue
        _tikAPI = State(initialValue: TikAPI(settings: s.tik))
        _tangoAPI = State(initialValue: TangoAPI(settings: s.tango))
        _stripAPI = State(initialValue: StripAPI(settings: s.strip))
        _minerAPI = State(initialValue: MinerAPI(settings: s.miner))
        _driveAPI = State(initialValue: DriveAPI(settings: s.drive))
    }

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack {
                CommandCenterView(
                    tikAPI: tikAPI,
                    tangoAPI: tangoAPI,
                    stripAPI: stripAPI,
                    minerAPI: minerAPI,
                    driveAPI: driveAPI,
                    onSelectTab: { newTab, subtab in
                        tab = newTab
                        if let subtab {
                            if newTab == 1 { recorderSection = subtab }
                            else if newTab == 2 { minerSection = subtab }
                            else if newTab == 3 { driveSection = subtab }
                        }
                    }
                )
            }
            .tabItem { Label("Overview", systemImage: "sparkles") }.tag(0)

            NavigationStack {
                RecordersRootView(
                    tikAPI: tikAPI,
                    tangoAPI: tangoAPI,
                    stripAPI: stripAPI,
                    selected: $recorderSection
                )
            }
            .tabItem { Label("Recorders", systemImage: "record.circle.fill") }.tag(1)

            NavigationStack { MinerRootView(api: minerAPI, selected: $minerSection) }
                .tabItem { Label("Miner", systemImage: "diamond.fill") }.tag(2)

            NavigationStack { DriveRootView(api: driveAPI, selected: $driveSection) }
                .tabItem { Label("Drive", systemImage: "externaldrive.fill") }
                .badge(driveUploadCount > 0 ? driveUploadCount : 0)
                .tag(3)

            NavigationStack {
                AIOSettingsView(settings: $settings) { updated in
                    settings = updated
                    tikAPI = TikAPI(settings: updated.tik)
                    tangoAPI = TangoAPI(settings: updated.tango)
                    stripAPI = StripAPI(settings: updated.strip)
                    minerAPI = MinerAPI(settings: updated.miner)
                    driveAPI = DriveAPI(settings: updated.drive)
                }
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }.tag(4)
        }
        .tint(Theme.blue)
        .task {
            while !Task.isCancelled {
                if let uploads = try? await driveAPI.uploadJobs() {
                    let active = uploads.filter { $0.isActive }.count
                    await MainActor.run { driveUploadCount = active }
                }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
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
        toastTask?.cancel()
        withAnimation { toast = msg }
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled {
                await MainActor.run { withAnimation { toast = nil } }
            }
        }
    }
}

// MARK: - Unified Recorders View (Tik + Tango)

struct RecordersRootView: View {
    let tikAPI: TikAPI
    let tangoAPI: TangoAPI
    let stripAPI: StripAPI
    @Binding var selected: Int

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    CapsuleFilterChip(
                        title: "TikTok / Twitch",
                        icon: "video.fill",
                        badgeColor: Theme.tiktokPink,
                        isSelected: selected == 0
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) { selected = 0 }
                    }

                    CapsuleFilterChip(
                        title: "Tango.me",
                        icon: "phone.fill",
                        badgeColor: Theme.tangoOrange,
                        isSelected: selected == 1
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) { selected = 1 }
                    }

                    CapsuleFilterChip(
                        title: "Stripchat",
                        icon: "flame.fill",
                        badgeColor: Theme.stripPink,
                        isSelected: selected == 2
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) { selected = 2 }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }

            if selected == 0 {
                TikRootView(api: tikAPI)
            } else if selected == 1 {
                TangoRootView(api: tangoAPI)
            } else {
                StripRootView(api: stripAPI)
            }
        }
        .background(AppBackground())
        .navigationTitle(selected == 0 ? "Tik Recorder"
                         : (selected == 1 ? "Tango Recorder" : "Stripchat Recorder"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Sub-tabs for miner + drive

struct MinerRootView: View {
    let api: MinerAPI
    @Binding var section: Int

    init(api: MinerAPI, selected: Binding<Int> = .constant(0)) {
        self.api = api
        self._section = selected
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    CapsuleFilterChip(title: "Miner", icon: "diamond.fill", isSelected: section == 0) {
                        withAnimation(.easeInOut(duration: 0.15)) { section = 0 }
                    }
                    CapsuleFilterChip(title: "Channels", icon: "tv.fill", isSelected: section == 1) {
                        withAnimation(.easeInOut(duration: 0.15)) { section = 1 }
                    }
                    CapsuleFilterChip(title: "Logs", icon: "list.bullet.rectangle", isSelected: section == 2) {
                        withAnimation(.easeInOut(duration: 0.15)) { section = 2 }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }

            switch section {
            case 0: DashboardView(api: api)
            case 1: ChannelsView(api: api)
            default: LogsView(api: api)
            }
        }
        .background(AppBackground())
        .navigationTitle(section == 0 ? "Points Miner"
                         : (section == 1 ? "Miner Channels" : "Miner Logs"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct DriveRootView: View {
    let api: DriveAPI
    @Binding var section: Int
    @State private var uploadCount = 0

    init(api: DriveAPI, selected: Binding<Int> = .constant(0)) {
        self.api = api
        self._section = selected
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    CapsuleFilterChip(title: "Files", icon: "folder.fill", isSelected: section == 0) {
                        withAnimation(.easeInOut(duration: 0.15)) { section = 0 }
                    }
                    CapsuleFilterChip(title: "Views", icon: "eye.fill", isSelected: section == 1) {
                        withAnimation(.easeInOut(duration: 0.15)) { section = 1 }
                    }
                    CapsuleFilterChip(
                        title: "Uploads",
                        icon: "arrow.up.circle.fill",
                        badge: uploadCount > 0 ? "\(uploadCount)" : nil,
                        badgeColor: Theme.telegramSky,
                        isSelected: section == 2
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) { section = 2 }
                    }
                    CapsuleFilterChip(title: "Local", icon: "internaldrive.fill", isSelected: section == 3) {
                        withAnimation(.easeInOut(duration: 0.15)) { section = 3 }
                    }
                    CapsuleFilterChip(title: "Logs", icon: "doc.plaintext.fill", isSelected: section == 4) {
                        withAnimation(.easeInOut(duration: 0.15)) { section = 4 }
                    }
                    CapsuleFilterChip(title: "Archiver", icon: "archivebox.fill", isSelected: section == 5) {
                        withAnimation(.easeInOut(duration: 0.15)) { section = 5 }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }

            switch section {
            case 0: FilesView(api: api)
            case 1: ViewsView(api: api)
            case 2: UploadsView(api: api)
            case 3: LocalView(api: api)
            case 4: DriveLogsView(api: api)
            case 5: ArchiverView(api: api)
            default: FilesView(api: api)
            }
        }
        .background(AppBackground())
        .navigationTitle("Tele-Drive")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            while !Task.isCancelled {
                if let uploads = try? await api.uploadJobs() {
                    let active = uploads.filter { $0.isActive }.count
                    await MainActor.run { uploadCount = active }
                }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }
}



// MARK: - Connect

struct AIOConnectScreen: View {
    let onConnect: (AIOSettings) -> Void

    @State private var host = ""
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
            strip: StripSettings(host: h, port: 8092),
            miner: MinerSettings(host: h, port: 8000, token: minerToken, refreshSeconds: 10),
            drive: DriveSettings(host: h, port: 8001, token: driveToken))
        // Verify at least one backend answers before entering.
        var ok = false
        if (try? await TikAPI(settings: s.tik).sources()) != nil { ok = true }
        if (try? await TangoAPI(settings: s.tango).streamers()) != nil { ok = true }
        if (try? await StripAPI(settings: s.strip).streamers()) != nil { ok = true }
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
