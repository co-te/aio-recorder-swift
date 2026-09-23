//
//  CommandCenterView.swift
//  AIO — Unified Command Center & Real-Time Telemetry Dashboard.
//

import SwiftUI

struct CommandCenterView: View {
    let tikAPI: TikAPI
    let tangoAPI: TangoAPI
    let stripAPI: StripAPI
    let minerAPI: MinerAPI
    let driveAPI: DriveAPI
    var onSelectTab: ((Int, Int?) -> Void)? = nil

    @State private var loading = false
    @State private var lastRefresh = Date()

    // Telemetry data
    @State private var tikRecordings: [TikRecording] = []
    @State private var tikSources: [TikSource] = []
    @State private var tangoStreamers: [TangoStreamer] = []
    @State private var stripStreamers: [StripStreamer] = []
    @State private var minerStreamers: [StreamerState] = []
    @State private var minerRunning: Bool?
    @State private var driveUsage: TDUsage?
    @State private var archiverStatus: ArchiverStatus?

    // Backend connectivity
    @State private var tikOnline: Bool?
    @State private var tangoOnline: Bool?
    @State private var stripOnline: Bool?
    @State private var minerOnline: Bool?
    @State private var driveOnline: Bool?

    // Action feedback
    @State private var actionBusy = false
    @State private var actionMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                headerView
                activeOperationsBanner
                serviceHealthRow
                telemetryBentoGrid
                liveStreamersSection
                quickActionsSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(AppBackground())
        .navigationTitle("Command Center")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await refreshAll() }
        .task {
            await refreshAll()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if !Task.isCancelled {
                    await refreshQuiet()
                }
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("⚡")
                    Text("Overview")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(Theme.textPrimary)
                }
                Text("Updated \(lastRefresh.formatted(date: .omitted, time: .standard))")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button {
                Task { await refreshAll() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.textPrimary)
                    .rotationEffect(.degrees(loading ? 360 : 0))
                    .animation(loading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: loading)
                    .padding(10)
                    .background(Theme.surfaceBg, in: Circle())
                    .overlay(Circle().stroke(Theme.surfaceBorder, lineWidth: 0.5))
            }
            .buttonStyle(BouncyButtonStyle())
            .disabled(loading)
        }
        .padding(.top, 4)
    }

    // MARK: - Live Activity / Active Banner

    private var activeTikRecordings: [TikRecording] {
        tikRecordings.filter { $0.isActive }
    }

    private var activeTangoStreamers: [TangoStreamer] {
        tangoStreamers.filter { $0.isRecording }
    }

    private var activeStripStreamers: [StripStreamer] {
        stripStreamers.filter { $0.isRecording }
    }

    private var hasActiveOperations: Bool {
        !activeTikRecordings.isEmpty || !activeTangoStreamers.isEmpty || !activeStripStreamers.isEmpty
    }

    @ViewBuilder
    private var activeOperationsBanner: some View {
        if hasActiveOperations {
            VStack(spacing: 12) {
                ForEach(activeTikRecordings) { rec in
                    activeRecordingRow(
                        platform: rec.platform.capitalized,
                        title: rec.user,
                        subtitle: "\(Fmt.duration(rec.elapsed)) · \(Fmt.bytes(rec.sizeBytes))",
                        tint: rec.platform == "tiktok" ? Theme.tiktokPink : Theme.twitch
                    ) {
                        onSelectTab?(1, 0)
                    }
                }

                ForEach(activeTangoStreamers) { streamer in
                    activeRecordingRow(
                        platform: "Tango",
                        title: streamer.handle,
                        subtitle: "\(Fmt.duration(Double(streamer.seconds))) · \(streamer.segments) segs",
                        tint: Theme.tangoOrange
                    ) {
                        onSelectTab?(1, 1)
                    }
                }

                ForEach(activeStripStreamers) { streamer in
                    activeRecordingRow(
                        platform: "Stripchat",
                        title: streamer.handle,
                        subtitle: "\(Fmt.duration(Double(streamer.seconds))) · \(streamer.segments) segs",
                        tint: Theme.stripPink
                    ) {
                        onSelectTab?(1, 2)
                    }
                }
            }
        } else {
            BentoCard {
                HStack(spacing: 14) {
                    PulsingRadar(color: Theme.green, size: 10)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("All Recorders Standing By")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.textPrimary)
                        Text("\(tikSources.count + tangoStreamers.count + stripStreamers.count) channels monitored · Standby")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "checkmark.shield.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.green.opacity(0.8))
                }
            }
        }
    }

    private func activeRecordingRow(platform: String, title: String, subtitle: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                PulsingRadar(color: Theme.red, size: 10)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("RECORDING")
                            .font(.caption2)
                            .fontWeight(.black)
                            .foregroundStyle(Theme.red)
                        Text("· \(platform)")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(tint)
                    }
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }

                Spacer()

                Image(systemName: "waveform")
                    .font(.title3)
                    .foregroundStyle(Theme.red.opacity(0.9))
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary.opacity(0.6))
            }
            .padding(14)
            .background(Theme.cardFallback)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Theme.red.opacity(0.45), lineWidth: 1)
            )
        }
        .buttonStyle(BouncyButtonStyle())
    }

    // MARK: - Service Health Row

    private var serviceHealthRow: some View {
        HStack(spacing: 8) {
            healthPill(title: "Tik", isOnline: tikOnline, icon: "video.fill") {
                onSelectTab?(1, 0)
            }
            healthPill(title: "Tango", isOnline: tangoOnline, icon: "phone.fill") {
                onSelectTab?(1, 1)
            }
            healthPill(title: "Strip", isOnline: stripOnline, icon: "flame.fill") {
                onSelectTab?(1, 2)
            }
            healthPill(title: "Miner", isOnline: minerOnline, icon: "diamond.fill") {
                onSelectTab?(2, nil)
            }
            healthPill(title: "Drive", isOnline: driveOnline, icon: "externaldrive.fill") {
                onSelectTab?(3, nil)
            }
        }
    }

    private func healthPill(title: String, isOnline: Bool?, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Circle()
                    .fill(isOnline == true ? Theme.green : (isOnline == false ? Theme.red : Color.gray))
                    .frame(width: 7, height: 7)
                Text(title)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Theme.surfaceBg)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .overlay(
                Capsule().strokeBorder(Theme.surfaceBorder, lineWidth: 0.5)
            )
        }
        .buttonStyle(BouncyButtonStyle())
    }

    // MARK: - Bento Telemetry Grid

    private var totalMinerPoints: Int {
        minerStreamers.reduce(0) { $0 + $1.points }
    }

    private var onlineStreamerCount: Int {
        let tikLive = tikSources.filter { $0.currentlyLive }.count
        let tangoLive = tangoStreamers.filter { $0.isLive }.count
        let stripLive = stripStreamers.filter { $0.isLive }.count
        let twitchLive = minerStreamers.filter { $0.isOnline }.count
        return tikLive + tangoLive + stripLive + twitchLive
    }

    private var telemetryBentoGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            MetricCard(
                icon: "diamond.fill",
                title: "Channel Points",
                value: Fmt.points(totalMinerPoints),
                subtitle: "\(minerStreamers.filter { $0.isOnline }.count) active miners",
                tint: Theme.twitch
            ) {
                onSelectTab?(2, 0)
            }

            MetricCard(
                icon: "cloud.fill",
                title: "Drive Daily",
                value: driveUsage != nil ? Fmt.bytes(driveUsage!.uploadedBytes) : "--",
                subtitle: driveUsage != nil ? "\(Int(driveUsage!.fractionUsed * 100))% of limit" : "No usage data",
                tint: Theme.telegramSky
            ) {
                onSelectTab?(3, 0)
            }

            MetricCard(
                icon: "dot.radiowaves.left.and.right",
                title: "Live Streamers",
                value: "\(onlineStreamerCount)",
                subtitle: "\(activeTikRecordings.count + activeTangoStreamers.count + activeStripStreamers.count) recording now",
                tint: Theme.tiktokPink
            ) {
                onSelectTab?(1, 0)
            }

            MetricCard(
                icon: "archivebox.fill",
                title: "Drive Archiver",
                value: archiverStatus?.active.running == true ? "Running" : "Idle",
                subtitle: "\(archiverStatus?.active.uploaded ?? 0) archived today",
                tint: Theme.tangoOrange
            ) {
                onSelectTab?(3, 5)
            }
        }
    }

    // MARK: - Live Now Section

    private var liveStreamers: [LiveStreamerItem] {
        var items: [LiveStreamerItem] = []
        for s in tikSources where s.currentlyLive {
            items.append(LiveStreamerItem(id: "tik-\(s.id)", platform: s.platform.capitalized, handle: s.user, title: s.quality ?? "best", isRecording: tikRecordings.contains { $0.isActive && $0.user == s.user }))
        }
        for s in tangoStreamers where s.isLive {
            items.append(LiveStreamerItem(id: "tango-\(s.handle)", platform: "Tango", handle: s.handle, title: "\(s.segments) segments", isRecording: s.isRecording))
        }
        for s in stripStreamers where s.isLive {
            items.append(LiveStreamerItem(id: "strip-\(s.handle)", platform: "Stripchat", handle: s.handle, title: "\(s.segments) segments", isRecording: s.isRecording))
        }
        for s in minerStreamers where s.isOnline {
            items.append(LiveStreamerItem(id: "miner-\(s.username)", platform: "Twitch", handle: s.username, title: s.game.isEmpty ? s.title : s.game, isRecording: false))
        }
        return items
    }

    private var liveStreamersSection: some View {
        BentoCard(
            headerIcon: "antenna.radiowaves.left.and.right",
            headerTitle: "Broadcasting Now",
            headerSubtitle: "\(liveStreamers.count) stream\(liveStreamers.count == 1 ? "" : "s") online",
            headerBadge: liveStreamers.isEmpty ? nil : "LIVE",
            badgeColor: Theme.red
        ) {
            if liveStreamers.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Image(systemName: "moon.stars.fill")
                            .font(.title3)
                            .foregroundStyle(Theme.textSecondary.opacity(0.7))
                        Text("No monitored streams are currently online")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.vertical, 12)
                    Spacer()
                }
            } else {
                VStack(spacing: 10) {
                    ForEach(liveStreamers.prefix(6)) { streamer in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(streamer.isRecording ? Theme.red : Theme.green)
                                .frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(streamer.handle)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(Theme.textPrimary)
                                    Text(streamer.platform)
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1)
                                        .background(streamer.platformColor.opacity(0.2), in: Capsule())
                                        .foregroundStyle(streamer.platformColor)
                                }
                                if !streamer.title.isEmpty {
                                    Text(streamer.title)
                                        .font(.caption2)
                                        .foregroundStyle(Theme.textSecondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            if streamer.isRecording {
                                StatusPill(text: "REC", color: Theme.red)
                            } else {
                                Button {
                                    switch streamer.platform.lowercased() {
                                    case "tango": onSelectTab?(1, 1)
                                    case "stripchat": onSelectTab?(1, 2)
                                    case "twitch": onSelectTab?(2, nil)
                                    default: onSelectTab?(1, 0)
                                    }
                                } label: {
                                    Image(systemName: "record.circle")
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.blue)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        if streamer.id != liveStreamers.prefix(6).last?.id {
                            Divider().background(Color.white.opacity(0.08))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Quick Actions Section

    private var quickActionsSection: some View {
        BentoCard(headerIcon: "bolt.fill", headerTitle: "Quick Commands", badgeColor: Theme.gold) {
            VStack(spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        GlassButton(title: "Check Tango", icon: "antenna.radiowaves.left.and.right", tint: Theme.tangoOrange) {
                            Task { await checkTango() }
                        }
                        GlassButton(title: "Check Strip", icon: "flame.fill", tint: Theme.stripPink) {
                            Task { await checkStrip() }
                        }
                        GlassButton(title: "Run Archiver", icon: "arrow.triangle.2.circlepath", tint: Theme.telegramSky) {
                            Task { await runArchiver() }
                        }
                    }
                }

                if let msg = actionMessage {
                    Text(msg)
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.top, 4)
                        .transition(.opacity)
                }
            }
        }
    }

    // MARK: - Actions

    private func checkTango() async {
        guard !actionBusy else { return }
        actionBusy = true
        withAnimation { actionMessage = "Checking Tango live status..." }
        do {
            let statuses = try await tangoAPI.check()
            let liveCount = statuses.values.filter { $0 == "recording" || $0 == "live" }.count
            withAnimation { actionMessage = "Tango check complete: \(liveCount) live" }
            await refreshQuiet()
        } catch {
            withAnimation { actionMessage = "Tango check failed: \(error.messageText)" }
        }
        actionBusy = false
    }

    private func checkStrip() async {
        guard !actionBusy else { return }
        actionBusy = true
        withAnimation { actionMessage = "Checking Stripchat live status..." }
        do {
            let statuses = try await stripAPI.check()
            let liveCount = statuses.values.filter { $0 == "recording" || $0 == "live" }.count
            withAnimation { actionMessage = "Stripchat check complete: \(liveCount) live" }
            await refreshQuiet()
        } catch {
            withAnimation { actionMessage = "Stripchat check failed: \(error.messageText)" }
        }
        actionBusy = false
    }

    private func runArchiver() async {
        guard !actionBusy else { return }
        actionBusy = true
        withAnimation { actionMessage = "Triggering Drive Archiver..." }
        do {
            let active = try await driveAPI.archiverRun()
            withAnimation { actionMessage = "Archiver triggered (\(active))" }
            await refreshQuiet()
        } catch {
            withAnimation { actionMessage = "Archiver trigger failed: \(error.messageText)" }
        }
        actionBusy = false
    }

    // MARK: - Data Loading

    private func refreshAll() async {
        loading = true
        await loadTelemetry()
        loading = false
        lastRefresh = Date()
    }

    private func refreshQuiet() async {
        await loadTelemetry()
        lastRefresh = Date()
    }

    private func loadTelemetry() async {
        do {
            let recs = try await tikAPI.active()
            let srcs = try await tikAPI.sources()
            await MainActor.run {
                self.tikRecordings = recs
                self.tikSources = srcs
                self.tikOnline = true
            }
        } catch {
            await MainActor.run { self.tikOnline = false }
        }

        do {
            let streamers = try await tangoAPI.streamers()
            await MainActor.run {
                self.tangoStreamers = streamers
                self.tangoOnline = true
            }
        } catch {
            await MainActor.run { self.tangoOnline = false }
        }

        do {
            let streamers = try await stripAPI.streamers()
            await MainActor.run {
                self.stripStreamers = streamers
                self.stripOnline = true
            }
        } catch {
            await MainActor.run { self.stripOnline = false }
        }

        do {
            let full = try await minerAPI.streamers()
            let running = try await minerAPI.minerStatus()
            await MainActor.run {
                self.minerStreamers = full.map {
                    StreamerState(
                        username: $0.username,
                        points: $0.points,
                        isOnline: $0.isOnline,
                        stream: $0.stream,
                        pfp: ""
                    )
                }
                self.minerRunning = running
                self.minerOnline = true
            }
        } catch {
            await MainActor.run { self.minerOnline = false }
        }

        do {
            let usage = try await driveAPI.usage()
            let archiver = try? await driveAPI.archiverStatus()
            await MainActor.run {
                self.driveUsage = usage
                self.archiverStatus = archiver
                self.driveOnline = true
            }
        } catch {
            await MainActor.run { self.driveOnline = false }
        }
    }
}

private struct LiveStreamerItem: Identifiable {
    let id: String
    let platform: String
    let handle: String
    let title: String
    let isRecording: Bool

    var platformColor: Color {
        switch platform.lowercased() {
        case "tiktok": return Theme.tiktokPink
        case "tango": return Theme.tangoOrange
        case "stripchat": return Theme.stripPink
        case "twitch": return Theme.twitch
        default: return Theme.blue
        }
    }
}
