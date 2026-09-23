//
//  SettingsView.swift — Comprehensive AIO Management, Diagnostics & Power-User Tools.
//

import SwiftUI
import LocalAuthentication
import AVFoundation

// MARK: - Security & Privacy Manager

final class SecurityManager: ObservableObject {
    static let shared = SecurityManager()
    
    @AppStorage("biometric_lock_enabled") var isBiometricEnabled: Bool = false
    @AppStorage("privacy_blur_enabled") var isPrivacyBlurEnabled: Bool = true
    @AppStorage("default_playback_speed") var defaultPlaybackSpeed: Double = 1.0
    @AppStorage("skip_step_seconds") var skipStepSeconds: Int = 10
    @AppStorage("active_network_profile") var activeProfile: String = "home" // "home" or "remote"
    
    @Published var isUnlocked: Bool = true

    func authenticate(completion: @escaping (Bool) -> Void) {
        guard isBiometricEnabled else {
            isUnlocked = true
            completion(true)
            return
        }
        let context = LAContext()
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Unlock AIO Controller") { success, _ in
                DispatchQueue.main.async {
                    self.isUnlocked = success
                    completion(success)
                }
            }
        } else {
            isUnlocked = true
            completion(true)
        }
    }
}

// MARK: - Service Health State

struct ServicePingResult: Identifiable {
    let id = UUID()
    let name: String
    let port: Int
    var isOnline: Bool? = nil
    var latencyMs: Int? = nil
    var message: String? = nil
}

// MARK: - Full Settings Hub

struct AIOSettingsView: View {
    @Binding var settings: AIOSettings
    let onApplied: (AIOSettings) -> Void

    // Individual Host / Port states
    @State private var tikHost = ""
    @State private var tikPort = ""
    @State private var tangoHost = ""
    @State private var tangoPort = ""
    @State private var stripHost = ""
    @State private var stripPort = ""
    @State private var minerHost = ""
    @State private var minerPort = ""
    @State private var minerToken = ""
    @State private var driveHost = ""
    @State private var drivePort = ""
    @State private var driveToken = ""

    // Quick-Fill Master Host
    @State private var masterHost = ""

    // Diagnostics & Tests
    @State private var testing = false
    @State private var servicePings: [ServicePingResult] = [
        ServicePingResult(name: "TikTok / Twitch", port: 8090),
        ServicePingResult(name: "Tango.me", port: 8091),
        ServicePingResult(name: "Stripchat", port: 8092),
        ServicePingResult(name: "Twitch Miner", port: 8000),
        ServicePingResult(name: "Tele-Drive", port: 8001)
    ]

    // Tele-Drive Quota & Settings
    @State private var driveUsage: TDUsage?
    @State private var maxConc = 2
    @State private var driveNote: String?
    @State private var confirmLogout = false

    // Server Operations
    @State private var serverActionBusy = false
    @State private var serverActionNote: String?

    // Local Storage / Cache
    @State private var cacheSizeBytes: Int64 = 0

    // Toast / Feedback
    @State private var toastMessage: String?

    // Profile Switcher (Home LAN vs Remote VPN)
    @AppStorage("profile_home_host") private var homeSavedHost = "192.168.110.58"
    @AppStorage("profile_remote_host") private var remoteSavedHost = ""
    @State private var selectedProfile = "home"

    // Security & Preferences
    @ObservedObject private var security = SecurityManager.shared

    private var driveAPI: DriveAPI { DriveAPI(settings: current().drive) }
    private var tikAPI: TikAPI { TikAPI(settings: current().tik) }
    private var tangoAPI: TangoAPI { TangoAPI(settings: current().tango) }
    private var stripAPI: StripAPI { StripAPI(settings: current().strip) }
    private var minerAPI: MinerAPI { MinerAPI(settings: current().miner) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                profileSwitcherCard
                masterHostQuickFillCard
                serviceHealthDiagnosticsCard
                serverOperationsCard
                storageAndCacheCard
                playbackPreferencesCard
                securityCard
                endpointsConfigAccordion
                backupAndRestoreCard
                saveFloatingButton
                aboutCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 36)
        }
        .background(AppBackground())
        .navigationTitle("Settings & Tools")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            fill()
            calculateCacheSize()
        }
        .task { await loadDrive() }
        .overlay(alignment: .bottom) {
            if let toastMessage {
                Text(toastMessage)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(Theme.blue.opacity(0.4), lineWidth: 1))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: - 1. Profile Switcher (Home LAN vs Remote / VPN)

    private var profileSwitcherCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Network Location Profile", icon: "network")
                
                Picker("Location", selection: $selectedProfile) {
                    Text("🏠 Home LAN").tag("home")
                    Text("🌐 Remote / VPN").tag("remote")
                }
                .pickerStyle(.segmented)
                .onChange(of: selectedProfile) { newProfile in
                    switchProfile(to: newProfile)
                }

                HStack {
                    Image(systemName: selectedProfile == "home" ? "house.fill" : "globe")
                        .foregroundStyle(selectedProfile == "home" ? Theme.green : Theme.cyan)
                    Text(selectedProfile == "home" ? "Home subnet (192.168.110.x)" : "Remote / Tailscale IP or Domain")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                }
            }
        }
    }

    private func switchProfile(to profile: String) {
        if profile == "home" {
            if !homeSavedHost.isEmpty {
                applySharedHost(homeSavedHost)
                showToast("Switched to Home LAN profile")
            }
        } else {
            if !remoteSavedHost.isEmpty {
                applySharedHost(remoteSavedHost)
                showToast("Switched to Remote profile")
            } else {
                showToast("Set your remote IP below to save profile")
            }
        }
    }

    // MARK: - 2. Master Host Quick-Fill

    private var masterHostQuickFillCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Master Host IP Quick-Fill", icon: "bolt.fill")
                
                SecondaryLabel("Enter your server IP once to configure all 5 services simultaneously.", font: .caption)

                HStack(spacing: 8) {
                    GlassField(icon: "server.rack", placeholder: "e.g. 192.168.110.58", text: $masterHost, keyboard: .decimalPad)

                    GlassButton(title: "Apply All", icon: "arrow.right.circle.fill", tint: Theme.blue, prominent: true) {
                        let trimmed = masterHost.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        applySharedHost(trimmed)
                        if selectedProfile == "home" {
                            homeSavedHost = trimmed
                        } else {
                            remoteSavedHost = trimmed
                        }
                        showToast("Updated all 5 services to \(trimmed)")
                    }
                }
            }
        }
    }

    private func applySharedHost(_ host: String) {
        tikHost = host
        tangoHost = host
        stripHost = host
        minerHost = host
        driveHost = host
    }

    // MARK: - 3. Service Health & Latency Diagnostics

    private var serviceHealthDiagnosticsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    CardHeader(title: "Live Diagnostics & Latency", icon: "waveform.path.ecg")
                    Spacer()
                    GlassButton(title: testing ? "Testing…" : "Test All", icon: "arrow.clockwise", tint: Theme.blue) {
                        Task { await testAllServices() }
                    }
                    .disabled(testing)
                }

                VStack(spacing: 8) {
                    ForEach(servicePings) { ping in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(ping.isOnline == true ? Theme.green : (ping.isOnline == false ? Theme.red : Color.gray.opacity(0.6)))
                                .frame(width: 8, height: 8)
                            
                            VStack(alignment: .leading, spacing: 1) {
                                Text(ping.name)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundStyle(Theme.textPrimary)
                                Text("Port :\(ping.port)")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            
                            Spacer()
                            
                            if let ms = ping.latencyMs {
                                Text("\(ms) ms")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundStyle(ms < 50 ? Theme.green : (ms < 150 ? Theme.gold : Theme.warn))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Theme.surfaceBg, in: Capsule())
                            }
                            
                            if let msg = ping.message {
                                Text(msg)
                                    .font(.caption2)
                                    .foregroundStyle(ping.isOnline == true ? Theme.green : Theme.red)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.vertical, 3)
                        
                        if ping.id != servicePings.last?.id {
                            Divider().overlay(Theme.textSecondary.opacity(0.1))
                        }
                    }
                }
            }
        }
    }

    private func testAllServices() async {
        testing = true
        defer { testing = false }
        let c = current()

        // 1. Tik (:8090)
        await testSingle(index: 0) {
            let start = Date()
            _ = try await TikAPI(settings: c.tik).sources()
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            return (true, ms, "OK")
        }

        // 2. Tango (:8091)
        await testSingle(index: 1) {
            let start = Date()
            _ = try await TangoAPI(settings: c.tango).streamers()
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            return (true, ms, "OK")
        }

        // 3. Strip (:8092)
        await testSingle(index: 2) {
            let start = Date()
            _ = try await StripAPI(settings: c.strip).streamers()
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            return (true, ms, "OK")
        }

        // 4. Miner (:8000)
        await testSingle(index: 3) {
            let start = Date()
            let running = try await MinerAPI(settings: c.miner).minerStatus()
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            return (true, ms, running ? "Running" : "Idle")
        }

        // 5. Drive (:8001)
        await testSingle(index: 4) {
            let start = Date()
            let auth = try await DriveAPI(settings: c.drive).checkAuth()
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            return (true, ms, auth ? "Authed" : "No Token")
        }
    }

    private func testSingle(index: Int, action: () async throws -> (Bool, Int, String)) async {
        do {
            let res = try await action()
            await MainActor.run {
                servicePings[index].isOnline = res.0
                servicePings[index].latencyMs = res.1
                servicePings[index].message = res.2
            }
        } catch {
            await MainActor.run {
                servicePings[index].isOnline = false
                servicePings[index].latencyMs = nil
                servicePings[index].message = "Offline"
            }
        }
    }

    // MARK: - 4. Unified Server Maintenance Center

    private var serverOperationsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Server Container Operations", icon: "shippingbox.fill")

                SecondaryLabel("Directly trigger maintenance and background tasks on your server.", font: .caption)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    serverActionButton(title: "Restart Miner", icon: "diamond.fill", tint: Theme.twitch) {
                        await restartMinerContainer()
                    }

                    serverActionButton(title: "Restart Tik Rec", icon: "video.fill", tint: Theme.tiktokPink) {
                        await restartTikContainer()
                    }

                    serverActionButton(title: "Run Archiver", icon: "archivebox.fill", tint: Theme.telegramSky) {
                        await triggerArchiver()
                    }

                    serverActionButton(title: "Sync Drive", icon: "arrow.triangle.2.circlepath", tint: Theme.green) {
                        await triggerDriveSync()
                    }

                    serverActionButton(title: "Sweep Temp Files", icon: "trash.fill", tint: Theme.warn) {
                        await sweepTempRecordings()
                    }

                    serverActionButton(title: "Drive Logout", icon: "rectangle.portrait.and.arrow.right", tint: Theme.red) {
                        confirmLogout = true
                    }
                }

                if let serverActionNote {
                    Text(serverActionNote)
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.top, 4)
                        .transition(.opacity)
                }
            }
        }
        .confirmationDialog("Log out of Telegram Drive session?", isPresented: $confirmLogout) {
            Button("Log Out", role: .destructive) {
                Task {
                    try? await driveAPI.logout()
                    showToast("Drive logged out")
                }
            }
        }
    }

    private func serverActionButton(title: String, icon: String, tint: Color, action: @escaping () async -> Void) -> some View {
        Button {
            Task {
                serverActionBusy = true
                await action()
                serverActionBusy = false
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.surfaceBg)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.surfaceBorder, lineWidth: 0.5))
        }
        .disabled(serverActionBusy)
    }

    private func restartMinerContainer() async {
        withAnimation { serverActionNote = "Signaling Twitch Miner restart..." }
        try? await minerAPI.applyRestart()
        withAnimation { serverActionNote = "Miner container rebooting." }
        showToast("Twitch Miner restarting")
    }

    private func restartTikContainer() async {
        withAnimation { serverActionNote = "Signaling TikTok Recorder restart..." }
        let key = try? await tikAPI.adminKey()
        try? await tikAPI.restartServer(key: key)
        withAnimation { serverActionNote = "TikTok recorder rebooting." }
        showToast("TikTok recorder restarting")
    }

    private func triggerArchiver() async {
        withAnimation { serverActionNote = "Triggering Drive Archiver..." }
        if let st = try? await driveAPI.archiverRun() {
            withAnimation { serverActionNote = "Archiver triggered (\(st))." }
            showToast("Archiver triggered (\(st))")
        }
    }

    private func triggerDriveSync() async {
        withAnimation { serverActionNote = "Requesting Drive sync..." }
        try? await driveAPI.sync()
        withAnimation { serverActionNote = "Drive sync requested." }
        showToast("Drive sync requested")
    }

    private func sweepTempRecordings() async {
        withAnimation { serverActionNote = "Sweeping finished recording history..." }
        _ = try? await stripAPI.check()
        _ = try? await tangoAPI.check()
        withAnimation { serverActionNote = "Sweep completed." }
        showToast("Orphan sweep completed")
    }

    // MARK: - 5. Storage & Local Cache Cleaner

    private var storageAndCacheCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Device Storage & Cache", icon: "internaldrive.fill")

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cached Video Previews")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textPrimary)
                        Text(Fmt.bytes(Int(cacheSizeBytes)))
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    GlassButton(title: "Clear Cache", icon: "trash", tint: Theme.warn) {
                        clearCache()
                    }
                }

                if let driveUsage {
                    Divider().overlay(Theme.textSecondary.opacity(0.12))
                    
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Telegram Daily Upload Quota")
                                .font(.subheadline)
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Text("\(Int(driveUsage.fractionUsed * 100))%")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(driveUsage.fractionUsed > 0.85 ? Theme.red : Theme.telegramSky)
                        }

                        ProgressView(value: driveUsage.fractionUsed)
                            .tint(driveUsage.fractionUsed > 0.85 ? Theme.red : Theme.telegramSky)

                        HStack {
                            Text("\(Fmt.bytes(driveUsage.uploadedBytes)) used · \(Fmt.bytes(driveUsage.remainingBytes)) left")
                                .font(.caption2)
                                .foregroundStyle(Theme.textSecondary)
                            Spacer()
                            Button("Reset Quota") {
                                Task {
                                    try? await driveAPI.resetUsage()
                                    await loadDrive()
                                    showToast("Quota counter reset")
                                }
                            }
                            .font(.caption2)
                            .foregroundStyle(Theme.blue)
                        }
                    }
                }
            }
        }
    }

    private func calculateCacheSize() {
        let tmp = FileManager.default.temporaryDirectory
        var size: Int64 = 0
        if let files = try? FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: [.fileSizeKey]) {
            for f in files {
                if let s = try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    size += Int64(s)
                }
            }
        }
        cacheSizeBytes = size
    }

    private func clearCache() {
        let tmp = FileManager.default.temporaryDirectory
        if let files = try? FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil) {
            for f in files {
                try? FileManager.default.removeItem(at: f)
            }
        }
        calculateCacheSize()
        showToast("Temporary cache cleared")
    }

    // MARK: - 6. Playback Preferences

    private var playbackPreferencesCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Media Player Preferences", icon: "play.circle.fill")

                HStack {
                    Text("Default Playback Speed")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Picker("Speed", selection: $security.defaultPlaybackSpeed) {
                        Text("1.0x").tag(1.0)
                        Text("1.25x").tag(1.25)
                        Text("1.5x").tag(1.5)
                        Text("2.0x").tag(2.0)
                    }
                    .pickerStyle(.menu)
                }

                Divider().overlay(Theme.textSecondary.opacity(0.12))

                HStack {
                    Text("Double-Tap Skip Interval")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Picker("Skip", selection: $security.skipStepSeconds) {
                        Text("5s").tag(5)
                        Text("10s").tag(10)
                        Text("15s").tag(15)
                        Text("30s").tag(30)
                    }
                    .pickerStyle(.menu)
                }
            }
        }
    }

    // MARK: - 7. Security & Privacy

    private var securityCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Security & Privacy", icon: "lock.shield.fill")

                Toggle("Face ID / Biometric Lock", isOn: $security.isBiometricEnabled)
                    .foregroundStyle(Theme.textPrimary)
                    .tint(Theme.blue)

                Divider().overlay(Theme.textSecondary.opacity(0.12))

                Toggle("App Switcher Privacy Mask", isOn: $security.isPrivacyBlurEnabled)
                    .foregroundStyle(Theme.textPrimary)
                    .tint(Theme.blue)
                
                SecondaryLabel("Blurs screen content when switching apps to protect stream and drive content.", font: .caption2)
            }
        }
    }

    // MARK: - 8. Endpoints Configuration Details

    private var endpointsConfigAccordion: some View {
        VStack(spacing: 12) {
            DisclosureGroup {
                VStack(spacing: 12) {
                    serviceFieldGroup(title: "TikTok / Twitch", icon: "video.fill", host: $tikHost, port: $tikPort, defaultPort: "8090")
                    serviceFieldGroup(title: "Tango.me", icon: "phone.fill", host: $tangoHost, port: $tangoPort, defaultPort: "8091")
                    serviceFieldGroup(title: "Stripchat", icon: "flame.fill", host: $stripHost, port: $stripPort, defaultPort: "8092")
                    serviceFieldGroup(title: "Twitch Miner", icon: "diamond.fill", host: $minerHost, port: $minerPort, defaultPort: "8000", token: $minerToken, tokenPlaceholder: "TTV_API_TOKEN")
                    serviceFieldGroup(title: "Tele-Drive", icon: "externaldrive.fill", host: $driveHost, port: $drivePort, defaultPort: "8001", token: $driveToken, tokenPlaceholder: "APP_TOKEN")
                }
                .padding(.top, 10)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(Theme.blue)
                    Text("Individual Service Ports & Tokens")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.textPrimary)
                }
            }
            .padding(14)
            .background(Theme.cardFallback)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.surfaceBorder, lineWidth: 0.5))
        }
    }

    private func serviceFieldGroup(title: String, icon: String, host: Binding<String>, port: Binding<String>, defaultPort: String, token: Binding<String>? = nil, tokenPlaceholder: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundStyle(Theme.blue).font(.caption)
                Text(title).font(.caption).fontWeight(.semibold).foregroundStyle(Theme.textPrimary)
            }
            HStack(spacing: 8) {
                GlassField(icon: "wifi", placeholder: "IP / Host", text: host, keyboard: .decimalPad)
                GlassField(icon: "number", placeholder: defaultPort, text: port, keyboard: .numberPad)
                    .frame(width: 88)
            }
            if let token, let tokenPlaceholder {
                GlassField(icon: "key.fill", placeholder: tokenPlaceholder, text: token, secure: true)
            }
        }
        .padding(10)
        .background(Theme.surfaceBg)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - 9. Backup & Restore (JSON Export / Import)

    private var backupAndRestoreCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Configuration Backup", icon: "arrow.triangle.2.circlepath.circle.fill")

                SecondaryLabel("Export or import your full connection setup without re-typing tokens.", font: .caption)

                HStack(spacing: 10) {
                    GlassButton(title: "Copy JSON", icon: "doc.on.doc.fill", tint: Theme.blue) {
                        exportToClipboard()
                    }

                    GlassButton(title: "Import JSON", icon: "arrow.down.doc.fill", tint: Theme.green) {
                        importFromClipboard()
                    }
                }
            }
        }
    }

    private func exportToClipboard() {
        let c = current()
        let dict: [String: Any] = [
            "tik": ["host": c.tik.host, "port": c.tik.port],
            "tango": ["host": c.tango.host, "port": c.tango.port],
            "strip": ["host": c.strip.host, "port": c.strip.port],
            "miner": ["host": c.miner.host, "port": c.miner.port, "token": c.miner.token],
            "drive": ["host": c.drive.host, "port": c.drive.port, "token": c.drive.token]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted),
           let str = String(data: data, encoding: .utf8) {
            UIPasteboard.general.string = str
            showToast("Config JSON copied to clipboard!")
        }
    }

    private func importFromClipboard() {
        guard let str = UIPasteboard.general.string,
              let data = str.data(using: .utf8),
              let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            showToast("Clipboard does not contain valid config JSON")
            return
        }
        if let tik = dict["tik"] as? [String: Any] {
            tikHost = tik["host"] as? String ?? tikHost
            tikPort = String(tik["port"] as? Int ?? 8090)
        }
        if let tango = dict["tango"] as? [String: Any] {
            tangoHost = tango["host"] as? String ?? tangoHost
            tangoPort = String(tango["port"] as? Int ?? 8091)
        }
        if let strip = dict["strip"] as? [String: Any] {
            stripHost = strip["host"] as? String ?? stripHost
            stripPort = String(strip["port"] as? Int ?? 8092)
        }
        if let miner = dict["miner"] as? [String: Any] {
            minerHost = miner["host"] as? String ?? minerHost
            minerPort = String(miner["port"] as? Int ?? 8000)
            minerToken = miner["token"] as? String ?? minerToken
        }
        if let drive = dict["drive"] as? [String: Any] {
            driveHost = drive["host"] as? String ?? driveHost
            drivePort = String(drive["port"] as? Int ?? 8001)
            driveToken = drive["token"] as? String ?? driveToken
        }
        apply()
        showToast("Config imported and applied!")
    }

    // MARK: - 10. Save Button

    private var saveFloatingButton: some View {
        GlassButton(title: "Save All Settings", icon: "checkmark.circle.fill", tint: Theme.blue, prominent: true) {
            apply()
            showToast("Settings saved successfully!")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    // MARK: - 11. About Card

    private var aboutCard: some View {
        VStack(spacing: 4) {
            Text("AIO Controller · Version 2.0")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.textSecondary)
            Text("Liquid Glass Native SwiftUI for iOS 16+")
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    // MARK: - Helpers

    private func fill() {
        tikHost = settings.tik.host
        tikPort = String(settings.tik.port)
        tangoHost = settings.tango.host
        tangoPort = String(settings.tango.port)
        stripHost = settings.strip.host
        stripPort = String(settings.strip.port)
        minerHost = settings.miner.host
        minerPort = String(settings.miner.port)
        minerToken = settings.miner.token
        driveHost = settings.drive.host
        drivePort = String(settings.drive.port)
        driveToken = settings.drive.token
        masterHost = settings.tik.host.isEmpty ? (settings.drive.host.isEmpty ? "192.168.110.58" : settings.drive.host) : settings.tik.host
    }

    private func current() -> AIOSettings {
        let cleanTik = tikHost.trimmingCharacters(in: .whitespaces)
        let cleanTango = tangoHost.trimmingCharacters(in: .whitespaces)
        let cleanStrip = stripHost.trimmingCharacters(in: .whitespaces)
        let cleanMiner = minerHost.trimmingCharacters(in: .whitespaces)
        let cleanDrive = driveHost.trimmingCharacters(in: .whitespaces)
        return AIOSettings(
            tik: TikSettings(
                host: cleanTik,
                port: Int(tikPort) ?? settings.tik.port),
            tango: TangoSettings(
                host: cleanTango,
                port: Int(tangoPort) ?? settings.tango.port),
            strip: StripSettings(
                host: cleanStrip,
                port: Int(stripPort) ?? settings.strip.port),
            miner: MinerSettings(
                host: cleanMiner,
                port: Int(minerPort) ?? settings.miner.port,
                token: minerToken,
                refreshSeconds: settings.miner.refreshSeconds),
            drive: DriveSettings(
                host: cleanDrive,
                port: Int(drivePort) ?? settings.drive.port,
                token: driveToken))
    }

    private func apply() {
        let s = current()
        s.save()
        onApplied(s)
    }

    private func loadDrive() async {
        driveUsage = try? await driveAPI.usage()
        if let n = try? await driveAPI.maxConcurrent() { maxConc = n }
    }

    private func showToast(_ msg: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            toastMessage = msg
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation {
                if toastMessage == msg {
                    toastMessage = nil
                }
            }
        }
    }
}
