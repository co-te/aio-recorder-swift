//
//  ArchiverView.swift — recording-archiver script progress (Tele-Drive + Google Drive dual offload).
//

import SwiftUI

struct ArchiverGDInfo: Decodable {
    var status: String = "idle"
    var needed: Int = 0
    var uploaded: Int = 0
    var current_category: String = ""
}

struct ArchiverTGInfo: Decodable {
    var status: String = "idle"
    var already: Int = 0
    var queued: Int = 0
    var pending: Int = 0
}

struct ArchiverActive: Decodable {
    var running: Bool = false
    var started: String = ""
    var total: Int = 0
    var queued: Int = 0
    var uploaded: Int = 0
    var deleted: Int = 0
    var skipped: Int = 0
    var still_local: Int? = nil
    var current: String = ""
    var gdrive: ArchiverGDInfo? = nil
    var teledrive: ArchiverTGInfo? = nil

    var completedCount: Int {
        max(deleted, uploaded + skipped)
    }

    var progressRatio: Double {
        guard total > 0 else { return 0.0 }
        return min(Double(completedCount) / Double(total), 1.0)
    }

    var progressPercent: Int {
        Int(progressRatio * 100)
    }

    var isGDActive: Bool {
        if !running { return false }
        let c = current.lowercased()
        let gdStatus = gdrive?.status.lowercased() ?? ""
        if c.contains("gdrive") || c.contains("drive") || gdStatus.contains("uploading") || gdStatus.contains("reading") {
            return true
        }
        return false
    }

    var isTGActive: Bool {
        if !running { return false }
        let c = current.lowercased()
        let tgStatus = teledrive?.status.lowercased() ?? ""
        if c.contains("telegram") || c.contains("pending") || (teledrive?.pending ?? 0) > 0 || tgStatus.contains("pending") || tgStatus.contains("queued") {
            return true
        }
        return false
    }
}

struct ArchiverDay: Decodable, Identifiable {
    var date: String = ""
    var runs: Int = 0
    var uploaded: Int = 0
    var deleted: Int = 0
    var skipped: Int = 0
    var id: String { date }
}

struct ArchiverStatus: Decodable {
    var active: ArchiverActive = ArchiverActive()
    var history: [ArchiverDay] = []
    var updated: String = ""
}

struct ArchiverView: View {
    let api: DriveAPI

    @State private var status: ArchiverStatus?
    @State private var errorText: String?
    @State private var runNote: String?
    @State private var runBusy = false

    var body: some View {
        content
            .background(AppBackground())
            .navigationTitle("Dual Archiver")
            .refreshable { await load() }
            .task {
                await load()
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    if !Task.isCancelled {
                        await loadQuiet()
                    }
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if let err = errorText, status == nil {
            ErrorStateView(message: err) { Task { await load() } }
        } else {
            ScrollView {
                VStack(spacing: 14) {
                    // MARK: - Manual Trigger
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            CardHeader(title: "Manual Control", icon: "play.circle")
                            Button {
                                Task { await runNow() }
                            } label: {
                                HStack(spacing: 8) {
                                    if runBusy {
                                        ProgressView()
                                            .tint(.white)
                                    } else {
                                        Image(systemName: "bolt.fill")
                                    }
                                    Text(runBusy ? "Requesting…" : "Run Archiver Now")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(Theme.blue.opacity(0.3), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .foregroundStyle(Theme.textPrimary)
                            }
                            .buttonStyle(BouncyButtonStyle())
                            .disabled(runBusy)

                            if let runNote {
                                SecondaryLabel(runNote, font: .caption)
                            }
                        }
                    }
                    .padding(.horizontal, 16)

                    // MARK: - Active Dual-Archiver Progress
                    if let a = status?.active {
                        overallProgressCard(a)
                            .padding(.horizontal, 16)

                        // MARK: - Dedicated Destination Indicators (Tele-Drive & Google Drive)
                        destinationsGrid(a)
                            .padding(.horizontal, 16)
                    }

                    // MARK: - History Section
                    let days = (status?.history ?? []).reversed()
                    if !days.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            SecondaryLabel("ARCHIVE HISTORY", font: .caption2)
                                .padding(.horizontal, 20)

                            ForEach(Array(days)) { d in
                                GlassCard {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            CardHeader(title: d.date, icon: "calendar")
                                            Spacer()
                                            Text("\(d.runs) run\(d.runs == 1 ? "" : "s")")
                                                .font(.caption2)
                                                .foregroundStyle(Theme.textSecondary)
                                        }
                                        SecondaryLabel(
                                            "Dual-verified & deleted: \(d.deleted) \(d.deleted == 1 ? "file" : "files") offloaded from Pi SSD"
                                        )
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                    }

                    if let u = status?.updated, !u.isEmpty {
                        SecondaryLabel("Updated \(u)", font: .caption2)
                            .padding(.top, 4)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private func overallProgressCard(_ a: ArchiverActive) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center) {
                    HStack(spacing: 8) {
                        if a.running {
                            PulsingRadar(color: Theme.cyan, size: 8)
                        } else {
                            Image(systemName: "checkmark.shield.fill")
                                .foregroundStyle(Theme.green)
                                .font(.subheadline)
                        }
                        Text(a.running ? "Dual-Archiver Active" : "Dual-Archiver Idle")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.textPrimary)
                    }

                    Spacer()

                    Text(a.running ? "IN PROGRESS" : "VERIFIED & IDLE")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background((a.running ? Theme.cyan : Theme.green).opacity(0.18), in: Capsule())
                        .foregroundStyle(a.running ? Theme.cyan : Theme.green)
                }

                if a.total > 0 {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Dual-Sync Offload Progress")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Text("\(a.progressPercent)% (\(a.completedCount)/\(a.total))")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(a.running ? Theme.cyan : Theme.green)
                        }

                        ProgressView(value: a.progressRatio)
                            .tint(a.running ? Theme.cyan : Theme.green)
                            .scaleEffect(x: 1, y: 1.5, anchor: .center)

                        HStack {
                            Text("SSD Offloaded: \(a.deleted)")
                                .font(.caption2)
                                .foregroundStyle(Theme.green)
                            Spacer()
                            if let still = a.still_local {
                                Text("Remaining local: \(still)")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                } else {
                    SecondaryLabel("No active archiving batch")
                }

                if a.running && !a.current.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(Theme.cyan)
                        Text(a.current)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                if !a.started.isEmpty {
                    HStack {
                        Image(systemName: "clock")
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                        SecondaryLabel("Run started: \(a.started)", font: .caption2)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func destinationsGrid(_ a: ArchiverActive) -> some View {
        VStack(spacing: 10) {
            // Destination 1: Tele-Drive (Telegram Saved Messages)
            BentoCard(
                headerIcon: "paperplane.fill",
                headerTitle: "Tele-Drive (Telegram)",
                headerSubtitle: "Saved Messages chunk storage",
                headerBadge: tgBadgeText(a),
                badgeColor: tgBadgeColor(a)
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Target Destination")
                                .font(.caption2)
                                .foregroundStyle(Theme.textSecondary)
                            Text("Telegram Saved Messages")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(Theme.textPrimary)
                        }
                        Spacer()
                        if let tg = a.teledrive, tg.pending > 0 {
                            Text("\(tg.pending) in queue")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Theme.telegramSky.opacity(0.2), in: Capsule())
                                .foregroundStyle(Theme.telegramSky)
                        } else if let tg = a.teledrive, tg.queued > 0 {
                            Text("\(tg.queued) synced this run")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundStyle(Theme.green)
                        } else {
                            Text("Up to date")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundStyle(Theme.green)
                        }
                    }

                    if a.isTGActive {
                        VStack(alignment: .leading, spacing: 6) {
                            if let tg = a.teledrive, tg.pending > 0 {
                                let totalTg = max(tg.queued, tg.pending)
                                let doneTg = max(totalTg - tg.pending, 0)
                                let ratio = totalTg > 0 ? Double(doneTg) / Double(totalTg) : 0.0
                                ProgressView(value: ratio)
                                    .tint(Theme.telegramSky)
                                    .scaleEffect(x: 1, y: 1.2, anchor: .center)
                            } else {
                                ProgressView()
                                    .tint(Theme.telegramSky)
                                    .scaleEffect(0.85)
                            }
                        }
                    }
                }
            }

            // Destination 2: Google Drive (rclone gdrive)
            BentoCard(
                headerIcon: "externaldrive.fill",
                headerTitle: "Google Drive (rclone)",
                headerSubtitle: "gdrive:Pi-Backups/<category>",
                headerBadge: gdBadgeText(a),
                badgeColor: gdBadgeColor(a)
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Destination Folder")
                                .font(.caption2)
                                .foregroundStyle(Theme.textSecondary)
                            Text("Pi-Backups/{tango, tik, strip, snapchat}")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(Theme.textPrimary)
                        }
                        Spacer()
                        if let gd = a.gdrive, !gd.current_category.isEmpty && a.isGDActive {
                            Text(gd.current_category.uppercased())
                                .font(.caption2)
                                .fontWeight(.bold)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Theme.twitch.opacity(0.25), in: Capsule())
                                .foregroundStyle(Theme.twitch)
                        } else if let gd = a.gdrive, gd.uploaded > 0 {
                            Text("\(gd.uploaded) uploaded")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundStyle(Theme.green)
                        } else {
                            Text("Verified")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundStyle(Theme.green)
                        }
                    }

                    if a.isGDActive {
                        VStack(alignment: .leading, spacing: 6) {
                            if let gd = a.gdrive, gd.needed > 0 {
                                let ratio = Double(min(gd.uploaded, gd.needed)) / Double(gd.needed)
                                ProgressView(value: ratio)
                                    .tint(Theme.twitch)
                                    .scaleEffect(x: 1, y: 1.2, anchor: .center)
                            } else {
                                ProgressView()
                                    .tint(Theme.twitch)
                                    .scaleEffect(0.85)
                            }
                        }
                    }
                }
            }
        }
    }

    private func tgBadgeText(_ a: ArchiverActive) -> String {
        if !a.running { return "SYNCED" }
        if a.isTGActive { return "UPLOADING" }
        return "WAITING"
    }

    private func tgBadgeColor(_ a: ArchiverActive) -> Color {
        if !a.running { return Theme.green }
        if a.isTGActive { return Theme.telegramSky }
        return Theme.textSecondary
    }

    private func gdBadgeText(_ a: ArchiverActive) -> String {
        if !a.running { return "SYNCED" }
        if a.isGDActive { return "UPLOADING" }
        return "WAITING"
    }

    private func gdBadgeColor(_ a: ArchiverActive) -> Color {
        if !a.running { return Theme.green }
        if a.isGDActive { return Theme.twitch }
        return Theme.textSecondary
    }

    // MARK: - Actions

    private func load() async {
        do {
            status = try await api.archiverStatus()
            errorText = nil
        } catch {
            errorText = error.messageText
        }
    }

    private func loadQuiet() async {
        if let s = try? await api.archiverStatus() {
            status = s
            errorText = nil
        }
    }

    private func runNow() async {
        runBusy = true
        defer { runBusy = false }
        do {
            let state = try await api.archiverRun()
            runNote = state == "already-requested" ? "Run already requested" : "Run requested — starting shortly"
        } catch {
            runNote = "Request failed: \(error.messageText)"
        }
    }
}
