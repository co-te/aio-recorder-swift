//
//  TikViews.swift — sources (monitors), active recordings, history, settings.
//

import SwiftUI

struct TikRootView: View {
    let api: TikAPI
    @State private var section = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $section) {
                Text("Sources").tag(0)
                Text("Recording").tag(1)
                Text("History").tag(2)
                Text("Config").tag(3)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            switch section {
            case 0: TikSourcesView(api: api)
            case 1: TikActiveView(api: api)
            case 2: TikHistoryView(api: api)
            default: TikConfigView(api: api)
            }
        }
        .background(AppBackground())
        .navigationTitle("Tik recorder")
    }
}

// MARK: - Sources

private struct TikSourcesView: View {
    let api: TikAPI

    @State private var items: [TikSource] = []
    @State private var errorText: String?
    @State private var showAdd = false
    @State private var logSource: TikSource?
    @State private var editing: TikSource?

    var body: some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .refreshable { await load() }
            .task { await load() }
            .sheet(isPresented: $showAdd, onDismiss: { Task { await load() } }) {
                TikAddSourceSheet(api: api)
            }
            .sheet(item: $logSource) { s in
                TikLogSheet(api: api, source: s)
            }
            .sheet(item: $editing, onDismiss: { Task { await load() } }) { s in
                TikEditSourceSheet(api: api, source: s)
            }
    }

    @ViewBuilder
    private var content: some View {
        if let err = errorText, items.isEmpty {
            ErrorStateView(message: err) { Task { await load() } }
        } else {
            ScrollView {
                VStack(spacing: 10) {
                    if items.isEmpty {
                        GlassCard {
                            SecondaryLabel("No sources — tap + to monitor someone.")
                                .frame(maxWidth: .infinity)
                                .padding(24)
                        }
                    } else {
                        ForEach(items) { s in
                            TikSourceCard(api: api, source: s,
                                          onLog: { logSource = s },
                                          onEdit: { editing = s },
                                          onChange: { Task { await load() } })
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
    }

    private func load() async {
        do {
            items = try await api.sources()
            errorText = nil
        } catch {
            errorText = error.messageText
        }
    }
}

private struct TikSourceCard: View {
    let api: TikAPI
    let source: TikSource
    let onLog: () -> Void
    let onEdit: () -> Void
    let onChange: () -> Void
    @State private var confirm = false

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: source.platform == "twitch" ? "tv.fill" : "music.note")
                        .foregroundStyle(source.platform == "twitch" ? Theme.twitch : Theme.textPrimary)
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.07), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("@\(source.user)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.textPrimary)
                        SecondaryLabel(
                            "\(source.platform) · every \(source.interval) min · \(source.quality ?? "best")",
                            font: .caption2)
                    }
                    Spacer()
                    StatusPill(
                        text: source.currentlyLive ? "LIVE" : (source.enabled ? "watching" : "paused"),
                        color: source.currentlyLive ? Theme.red : (source.enabled ? Theme.green : Theme.textSecondary))
                }

                if let err = source.lastError, !err.isEmpty {
                    Text(err)
                        .font(.caption2)
                        .foregroundStyle(Theme.warn)
                        .lineLimit(2)
                }
                if let check = source.lastCheck, !check.isEmpty {
                    SecondaryLabel("Checked \(Fmt.iso(check))", font: .caption2)
                }

                HStack(spacing: 8) {
                    Button(source.enabled ? "Pause" : "Resume") {
                        Task {
                            try? await api.updateSource(source.id, enabled: !source.enabled)
                            onChange()
                        }
                    }
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background((source.enabled ? Theme.warn : Theme.green).opacity(0.25), in: Capsule())
                    .foregroundStyle(source.enabled ? Theme.warn : Theme.green)

                    Button("Check now") {
                        Task {
                            try? await api.checkNow(source.id)
                            onChange()
                        }
                    }
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Theme.blue.opacity(0.25), in: Capsule())
                    .foregroundStyle(Theme.blue)

                    Button("Record") {
                        Task {
                            try? await api.startNow(source.id)
                            onChange()
                        }
                    }
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Theme.red.opacity(0.25), in: Capsule())
                    .foregroundStyle(Theme.red)

                    Spacer()

                    Button { onLog() } label: {
                        Image(systemName: "doc.text")
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Button { onEdit() } label: {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Button(role: .destructive) { confirm = true } label: {
                        Image(systemName: "trash")
                    }
                    .tint(.red)
                }
            }
            .padding(14)
        }
        .confirmationDialog("Remove @\(source.user)?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                Task {
                    try? await api.deleteSource(source.id)
                    onChange()
                }
            }
        }
    }
}

private struct TikAddSourceSheet: View {
    let api: TikAPI
    @Environment(\.dismiss) private var dismiss

    @State private var platform = "tiktok"
    @State private var user = ""
    @State private var url = ""
    @State private var interval = "3"
    @State private var quality = "best"
    @State private var busy = false
    @State private var err: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Source") {
                    Picker("Platform", selection: $platform) {
                        Text("TikTok").tag("tiktok")
                        Text("Twitch").tag("twitch")
                    }
                    TextField("Username (without @)", text: $user)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Direct URL (optional)", text: $url)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section("Options") {
                    TextField("Check interval minutes", text: $interval)
                        .keyboardType(.numberPad)
                    TextField("Quality (best, 1080p…)", text: $quality)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                if let err {
                    Section { Text(err).foregroundStyle(.red).font(.caption) }
                }
            }
            .navigationTitle("Monitor source")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { Task { await add() } }
                        .disabled(busy || user.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func add() async {
        busy = true
        defer { busy = false }
        do {
            try await api.addSource(platform: platform,
                                    user: user.trimmingCharacters(in: .whitespaces),
                                    interval: Int(interval) ?? 3,
                                    quality: quality.trimmingCharacters(in: .whitespaces),
                                    url: url.trimmingCharacters(in: .whitespaces))
            dismiss()
        } catch {
            err = error.messageText
        }
    }
}

private struct TikEditSourceSheet: View {
    let api: TikAPI
    let source: TikSource
    @Environment(\.dismiss) private var dismiss

    @State private var interval: String
    @State private var quality: String
    @State private var duration: String
    @State private var outputDir: String
    @State private var busy = false
    @State private var err: String?

    init(api: TikAPI, source: TikSource) {
        self.api = api
        self.source = source
        _interval = State(initialValue: String(source.interval))
        _quality = State(initialValue: source.quality ?? "best")
        _duration = State(initialValue: source.duration.map(String.init) ?? "")
        _outputDir = State(initialValue: source.outputDir ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Check frequency") {
                    TextField("Minutes between checks", text: $interval)
                        .keyboardType(.numberPad)
                }
                Section("Quality") {
                    TextField("best, 1080p, 720p…", text: $quality)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section("Max duration (optional)") {
                    TextField("Seconds, blank = unlimited", text: $duration)
                        .keyboardType(.numberPad)
                }
                Section("Output folder (optional)") {
                    TextField("Blank = server default", text: $outputDir)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                if let err {
                    Section { Text(err).foregroundStyle(.red).font(.caption) }
                }
            }
            .navigationTitle("@\(source.user)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }.disabled(busy)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() async {
        busy = true
        defer { busy = false }
        do {
            try await api.updateSource(
                source.id,
                interval: Int(interval) ?? source.interval,
                quality: quality.trimmingCharacters(in: .whitespaces),
                duration: Int(duration),
                outputDir: outputDir.trimmingCharacters(in: .whitespaces).isEmpty ? nil : outputDir.trimmingCharacters(in: .whitespaces))
            dismiss()
        } catch {
            err = error.messageText
        }
    }
}

private struct TikLogSheet: View {
    let api: TikAPI
    let source: TikSource
    @State private var lines: [String] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    if lines.isEmpty {
                        SecondaryLabel("No log lines.")
                    } else {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Theme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding()
            }
            .background(AppBackground())
            .navigationTitle("@\(source.user) log")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                lines = (try? await api.monitorLog(source.id)) ?? []
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Active

private struct TikActiveView: View {
    let api: TikAPI

    @State private var items: [TikRecording] = []
    @State private var errorText: String?

    var body: some View {
        content
            .refreshable { await load() }
            .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if let err = errorText, items.isEmpty {
            ErrorStateView(message: err) { Task { await load() } }
        } else {
            ScrollView {
                VStack(spacing: 10) {
                    if items.isEmpty {
                        GlassCard {
                            VStack(spacing: 8) {
                                Image(systemName: "record.circle")
                                    .font(.largeTitle)
                                    .foregroundStyle(Theme.textSecondary)
                                SecondaryLabel("Nothing recording right now.")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(24)
                        }
                    } else {
                        ForEach(items) { r in
                            TikRecordingCard(name: "@\(r.user)",
                                             detail: "\(r.platform) · \(Fmt.duration(r.elapsed)) · \(Fmt.bytes(r.sizeBytes))",
                                             status: r.status,
                                             color: Theme.red) {
                                Task {
                                    try? await api.stopRecording(r.id)
                                    await load()
                                }
                            } stopTitle: { "Stop" }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
    }

    private func load() async {
        do {
            items = try await api.active()
            errorText = nil
        } catch {
            errorText = error.messageText
        }
    }
}

// MARK: - History

private struct TikHistoryView: View {
    let api: TikAPI

    @State private var items: [TikRecording] = []
    @State private var errorText: String?

    var body: some View {
        content
            .refreshable { await load() }
            .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if let err = errorText, items.isEmpty {
            ErrorStateView(message: err) { Task { await load() } }
        } else {
            ScrollView {
                VStack(spacing: 10) {
                    if items.isEmpty {
                        GlassCard {
                            SecondaryLabel("No past recordings.")
                                .frame(maxWidth: .infinity)
                                .padding(24)
                        }
                    } else {
                        ForEach(items.prefix(50)) { r in
                            TikRecordingCard(name: "@\(r.user)",
                                             detail: "\(Fmt.iso(r.startTime)) · \(Fmt.duration(r.elapsed)) · \(Fmt.bytes(r.sizeBytes))",
                                             status: r.status,
                                             color: r.status == "completed" ? Theme.green : Theme.warn) {
                                Task {
                                    try? await api.deleteRecording(r.id)
                                    await load()
                                }
                            } stopTitle: { "Delete" }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
    }

    private func load() async {
        do {
            items = try await api.history()
            errorText = nil
        } catch {
            errorText = error.messageText
        }
    }
}

private struct TikRecordingCard: View {
    let name: String
    let detail: String
    let status: String
    let color: Color
    let onAction: () -> Void
    let stopTitle: () -> String

    var body: some View {
        GlassCard {
            HStack(spacing: 12) {
                Image(systemName: "record.circle.fill")
                    .foregroundStyle(color)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.textPrimary)
                    SecondaryLabel(detail, font: .caption2)
                }
                Spacer()
                VStack(spacing: 6) {
                    StatusPill(text: status, color: color)
                    Button(stopTitle()) { onAction() }
                        .font(.caption2)
                        .foregroundStyle(Theme.red)
                }
            }
            .padding(14)
        }
    }
}

// MARK: - Config

private struct TikConfigView: View {
    let api: TikAPI

    @State private var outputDir = ""
    @State private var quality = "best"
    @State private var proxy = ""
    @State private var interval = "2"
    @State private var autoConvert = true
    @State private var loaded = false
    @State private var note: String?
    @State private var err: String?
    @State private var sessionid = ""
    @State private var idc = "useast2a"
    @State private var hasCookies = false
    @State private var tgApiId = ""
    @State private var tgApiHash = ""
    @State private var tgChatId = "me"
    @State private var hasTelegram = false
    @State private var versionInfo = ""
    @State private var confirmRestart = false
    @State private var proxyInfo = ""
    @State private var proxyManual = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        CardHeader(title: "Recorder defaults", icon: "slider.horizontal.3")
                        GlassField(icon: "folder", placeholder: "Output dir", text: $outputDir)
                        GlassField(icon: "sparkles", placeholder: "Quality (best, 1080p…)", text: $quality)
                        GlassField(icon: "network", placeholder: "Proxy (optional)", text: $proxy)
                        GlassField(icon: "timer", placeholder: "Check interval minutes", text: $interval, keyboard: .numberPad)
                        Toggle("Auto-convert to MP4", isOn: $autoConvert)
                            .tint(Theme.blue)
                            .foregroundStyle(Theme.textPrimary)
                    }
                }
                GlassButton(title: "Save", icon: "checkmark", tint: Theme.blue, prominent: true) {
                    Task { await save() }
                }
                .frame(maxWidth: .infinity)

                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        CardHeader(title: "TikTok cookies", icon: "lock.shield")
                        SecondaryLabel(hasCookies ? "Cookies stored on server." : "No cookies stored — WAF blocks likely.", font: .caption2)
                        GlassField(icon: "number", placeholder: "sessionid_ss", text: $sessionid, secure: true)
                        GlassField(icon: "network", placeholder: "tt-target-idc", text: $idc)
                        HStack {
                            GlassButton(title: "Save cookies", icon: "checkmark", tint: Theme.blue) {
                                Task { await saveCookies() }
                            }
                            Spacer()
                        }
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        CardHeader(title: "Telegram alerts", icon: "paperplane")
                        SecondaryLabel(hasTelegram ? "Telegram linked." : "Not linked.", font: .caption2)
                        GlassField(icon: "number", placeholder: "api_id", text: $tgApiId, keyboard: .numberPad)
                        GlassField(icon: "key.fill", placeholder: "api_hash", text: $tgApiHash, secure: true)
                        GlassField(icon: "person", placeholder: "chat_id (default me)", text: $tgChatId)
                        HStack {
                            GlassButton(title: "Save telegram", icon: "checkmark", tint: Theme.blue) {
                                Task { await saveTelegram() }
                            }
                            Spacer()
                        }
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        CardHeader(title: "Server", icon: "server.rack")
                        if !versionInfo.isEmpty {
                            SecondaryLabel(versionInfo, font: .caption)
                        }
                        HStack(spacing: 10) {
                            GlassButton(title: "Version", icon: "info.circle", tint: Theme.blue) {
                                Task { await loadVersion() }
                            }
                            GlassButton(title: "Restart", icon: "arrow.triangle.2.circlepath", tint: Theme.red) {
                                confirmRestart = true
                            }
                        }
                    }
                }
                .confirmationDialog("Restart the tik recorder container?", isPresented: $confirmRestart) {
                    Button("Restart", role: .destructive) {
                        Task { await restart() }
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        CardHeader(title: "Proxy rotation", icon: "network")
                        if proxyInfo.isEmpty {
                            SecondaryLabel("Tap refresh for pool status.", font: .caption)
                        } else {
                            SecondaryLabel(proxyInfo, font: .caption)
                        }
                        GlassField(icon: "lock", placeholder: "Fixed proxy override (blank = auto)", text: $proxyManual)
                        HStack(spacing: 10) {
                            GlassButton(title: "Status", icon: "arrow.clockwise", tint: Theme.blue) {
                                Task { await loadProxy() }
                            }
                            GlassButton(title: "Rotate", icon: "arrow.triangle.2.circlepath", tint: Theme.warn) {
                                Task { await rotateProxy() }
                            }
                        }
                        HStack {
                            GlassButton(title: "Save override", icon: "checkmark", tint: Theme.blue) {
                                Task { await saveProxyOverride() }
                            }
                            Spacer()
                        }
                    }
                }
                if let note {
                    SecondaryLabel(note, font: .caption)
                }
                if let err {
                    Text(err).font(.caption).foregroundStyle(Theme.red)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .task { await load() }
    }

    private func load() async {
        guard !loaded else { return }
        do {
            let s = try await api.getSettings()
            outputDir = s.outputDir
            quality = s.defaultQuality
            proxy = s.proxy
            proxyManual = s.proxy
            interval = String(s.defaultInterval)
            autoConvert = s.autoConvert
            let integ = try await api.getIntegrations()
            sessionid = integ.cookies.sessionid
            idc = integ.cookies.ttTargetIdc
            hasCookies = integ.cookies.hasCookies
            tgApiId = integ.telegram.apiId
            tgApiHash = integ.telegram.apiHash
            tgChatId = integ.telegram.chatId
            hasTelegram = integ.telegram.hasTelegram
            loaded = true
        } catch {
            err = error.messageText
        }
    }

    private func save() async {
        do {
            try await api.saveSettings(TikSettingsData(
                outputDir: outputDir,
                defaultQuality: quality,
                proxy: proxy,
                defaultDuration: nil,
                defaultInterval: Int(interval) ?? 2,
                autoConvert: autoConvert))
            note = "Saved."
            err = nil
        } catch {
            err = error.messageText
        }
    }

    private func saveCookies() async {
        do {
            try await api.saveCookies(sessionid: sessionid, ttTargetIdc: idc)
            hasCookies = !sessionid.isEmpty
            note = "Cookies saved."
            err = nil
        } catch {
            err = error.messageText
        }
    }

    private func saveTelegram() async {
        do {
            try await api.saveTelegram(apiId: tgApiId, apiHash: tgApiHash, chatId: tgChatId)
            hasTelegram = !tgApiId.isEmpty
            note = "Telegram saved."
            err = nil
        } catch {
            err = error.messageText
        }
    }

    private func loadVersion() async {
        let key = try? await api.adminKey()
        let v = try? await api.serverVersion(key: key)
        versionInfo = "Installed \(v?.current ?? "?") · latest \(v?.latest ?? "?")"
    }

    private func restart() async {
        do {
            let key = try? await api.adminKey()
            try await api.restartServer(key: key)
            note = "Restart signal sent — container is coming back."
        } catch {
            err = error.messageText
        }
    }

    private func loadProxy() async {
        do {
            let p = try await api.proxyStatus()
            var lines = ["pool \(p.poolSize) · rotations \(p.rotations)"]
            for key in p.assignments.keys.sorted() {
                let short = key.replacingOccurrences(of: "tiktok:", with: "@")
                lines.append("\(short) → \(shortHost(p.assignments[key] ?? ""))")
            }
            if !p.lastError.isEmpty { lines.append(p.lastError) }
            proxyInfo = lines.joined(separator: "\n")
            err = nil
        } catch {
            err = error.messageText
        }
    }

    private func shortHost(_ proxy: String) -> String {
        let parts = proxy.split(separator: ":")
        return parts.count >= 2 ? String(parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "/"))) : proxy
    }

    private func rotateProxy() async {
        do {
            let cur = try await api.rotateProxy()
            proxyInfo = "Now using \(cur)"
        } catch {
            err = error.messageText
        }
    }

    private func saveProxyOverride() async {
        // Reuses the main settings save with the proxy field patched.
        do {
            try await api.saveSettings(TikSettingsData(
                outputDir: outputDir,
                defaultQuality: quality,
                proxy: proxyManual.trimmingCharacters(in: .whitespaces),
                defaultDuration: nil,
                defaultInterval: Int(interval) ?? 3,
                autoConvert: autoConvert))
            proxy = proxyManual.trimmingCharacters(in: .whitespaces)
            note = proxyManual.isEmpty ? "Auto rotation enabled." : "Fixed proxy saved."
            err = nil
        } catch {
            err = error.messageText
        }
    }
}
