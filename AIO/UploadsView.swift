//
//  UploadsView.swift — background upload jobs + phone photo/library upload.
//

import SwiftUI
import PhotosUI

struct UploadsView: View {
    let api: DriveAPI

    @State private var jobs: [TDUploadJob] = []
    @State private var folders: [TDFolder] = []
    @State private var target: TDFolder?
    @State private var errorText: String?
    @State private var pickerItem: PhotosPickerItem?
    @State private var uploading = false
    @State private var uploadNote: String?
    @State private var actionBusy = false

    private var activeJobs: [TDUploadJob] { jobs.filter(\.isActive) }
    private var completedJobs: [TDUploadJob] { jobs.filter { !$0.isActive } }

    var body: some View {
        content
            .background(AppBackground())
            .navigationTitle("Uploads")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            Task { await pauseAll() }
                        } label: {
                            Label("Pause all", systemImage: "pause.fill")
                        }
                        Button {
                            Task { await resumeAll() }
                        } label: {
                            Label("Resume all", systemImage: "play.fill")
                        }
                        Button(role: .destructive) {
                            Task { await cancelAll() }
                        } label: {
                            Label("Cancel all", systemImage: "xmark.circle")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textPrimary)
                    }
                }
            }
            .refreshable { await load() }
            .task {
                folders = (try? await api.folders()) ?? []
                if target == nil { target = folders.first }
                while !Task.isCancelled {
                    await loadQuiet()
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                }
            }
            .onChange(of: pickerItem) { item in
                guard let item else { return }
                Task { await uploadPicked(item) }
            }
    }

    @ViewBuilder
    private var content: some View {
        if let err = errorText, jobs.isEmpty {
            ErrorStateView(message: err) { Task { await load() } }
        } else {
            ScrollView {
                VStack(spacing: 14) {
                    // Queue Status & Batch Controls
                    queueOverviewCard

                    // Upload From Phone
                    phoneUploadCard

                    // Active Jobs
                    if !activeJobs.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                PulsingRadar(color: Theme.telegramSky, size: 7)
                                Text("ACTIVE UPLOADS (\(activeJobs.count))")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(Theme.telegramSky)
                                Spacer()
                            }
                            .padding(.horizontal, 20)

                            ForEach(activeJobs) { j in
                                JobCard(api: api, job: j) { Task { await load() } }
                                    .padding(.horizontal, 16)
                            }
                        }
                    }

                    // Recent Completed Jobs
                    if !completedJobs.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.textSecondary)
                                Text("RECENT JOBS (\(completedJobs.count))")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(Theme.textSecondary)
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 4)

                            ForEach(completedJobs.prefix(25)) { j in
                                JobCard(api: api, job: j) { Task { await load() } }
                                    .padding(.horizontal, 16)
                            }
                        }
                    }

                    if jobs.isEmpty {
                        BentoCard(headerIcon: "arrow.up.circle.fill", headerTitle: "No Uploads in Queue", badgeColor: Theme.telegramSky) {
                            VStack(spacing: 8) {
                                Image(systemName: "icloud.and.arrow.up")
                                    .font(.system(size: 36))
                                    .foregroundStyle(Theme.textSecondary.opacity(0.6))
                                    .padding(.top, 6)
                                Text("Files uploaded from your phone or the server archiver will appear here with live transfer progress.")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 12)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.top, 6)
                .padding(.bottom, 32)
            }
        }
    }

    // MARK: - Queue Overview Card

    private var queueOverviewCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            if !activeJobs.isEmpty {
                                PulsingRadar(color: Theme.telegramSky, size: 8)
                            } else {
                                Circle().fill(Theme.green).frame(width: 8, height: 8)
                            }
                            Text(activeJobs.isEmpty ? "Upload Queue Idle" : "\(activeJobs.count) Uploading")
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundStyle(Theme.textPrimary)
                        }
                        Text("\(completedJobs.count) finished · \(folders.count) destination channels")
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()

                    if !activeJobs.isEmpty {
                        HStack(spacing: 8) {
                            Button {
                                Task { await pauseAll() }
                            } label: {
                                Image(systemName: "pause.fill")
                                    .font(.caption)
                                    .padding(8)
                                    .background(Theme.surfaceBg, in: Circle())
                                    .foregroundStyle(Theme.warn)
                            }
                            .buttonStyle(BouncyButtonStyle())

                            Button {
                                Task { await cancelAll() }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption)
                                    .padding(8)
                                    .background(Theme.surfaceBg, in: Circle())
                                    .foregroundStyle(Theme.red)
                            }
                            .buttonStyle(BouncyButtonStyle())
                        }
                    }
                }
            }
            .padding(14)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Phone Upload Card

    private var phoneUploadCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Upload from phone", icon: "iphone")

                VStack(alignment: .leading, spacing: 6) {
                    Text("Target Folder")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)

                    HStack {
                        Image(systemName: "folder.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.telegramSky)

                        Picker("To folder", selection: Binding(
                            get: { target?.id ?? "" },
                            set: { id in target = folders.first(where: { $0.id == id }) }
                        )) {
                            ForEach(folders) { f in
                                Text(f.name).tag(f.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(Theme.telegramSky)

                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                PhotosPicker(selection: $pickerItem, matching: .any(of: [.images, .videos])) {
                    HStack(spacing: 8) {
                        if uploading {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "photo.badge.plus")
                                .font(.subheadline)
                        }
                        Text(uploading ? "Uploading to Telegram…" : "Pick Photo or Video")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(
                        LinearGradient(colors: [Theme.telegramSky.opacity(0.35), Theme.blue.opacity(0.45)], startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .foregroundStyle(Theme.textPrimary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Theme.telegramSky.opacity(0.4), lineWidth: 0.5)
                    )
                }
                .buttonStyle(BouncyButtonStyle())
                .disabled(uploading || target == nil)

                if let uploadNote {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.caption2)
                        Text(uploadNote)
                            .font(.caption2)
                    }
                    .foregroundStyle(Theme.telegramSky)
                }
            }
            .padding(14)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Actions

    private func pauseAll() async {
        guard !actionBusy else { return }
        actionBusy = true
        defer { actionBusy = false }
        try? await api.pauseAll()
        await load()
    }

    private func resumeAll() async {
        guard !actionBusy else { return }
        actionBusy = true
        defer { actionBusy = false }
        try? await api.resumeAll()
        await load()
    }

    private func cancelAll() async {
        guard !actionBusy else { return }
        actionBusy = true
        defer { actionBusy = false }
        try? await api.cancelAll()
        await load()
    }

    private func load() async {
        do {
            jobs = try await api.uploadJobs()
            errorText = nil
        } catch {
            errorText = error.messageText
        }
    }

    /// Background poll: never flashes errors, never clears the list.
    private func loadQuiet() async {
        if let fresh = try? await api.uploadJobs() {
            jobs = fresh
        }
    }

    private func uploadPicked(_ item: PhotosPickerItem) async {
        guard let dest = target else { return }
        uploading = true
        defer {
            uploading = false
            pickerItem = nil
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                uploadNote = "Couldn't read that file."
                return
            }
            let rawName = item.itemIdentifier ?? "upload_\(Int(Date().timeIntervalSince1970))"
            let safeName = rawName.split(separator: "/").last.map(String.init) ?? "upload"
            let ext = (item.supportedContentTypes.first?.preferredFilenameExtension).map { ".\($0)" } ?? ""
            try await api.uploadFile(
                data: data,
                filename: "\(safeName)\(ext)",
                mime: item.supportedContentTypes.first?.preferredMIMEType ?? "application/octet-stream",
                peerType: dest.peerType, peerId: dest.peerId)
            uploadNote = "Queued — watch progress below."
            await load()
        } catch {
            uploadNote = error.messageText
        }
    }
}

// MARK: - Job Card

private struct JobCard: View {
    let api: DriveAPI
    let job: TDUploadJob
    let onChange: () -> Void

    init(api: DriveAPI, job: TDUploadJob, onChange: @escaping () -> Void) {
        self.api = api
        self.job = job
        self.onChange = onChange
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: fileIcon)
                        .font(.subheadline)
                        .foregroundStyle(pillColor)

                    Text(job.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)

                    Spacer()

                    StatusPill(text: job.status.uppercased(), color: pillColor)
                }

                // Progress Bar
                VStack(spacing: 5) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.08))
                                .frame(height: 6)

                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [pillColor.opacity(0.8), pillColor],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(6, geo.size.width * CGFloat(job.fraction)), height: 6)
                        }
                    }
                    .frame(height: 6)

                    HStack {
                        Text("\(Fmt.bytes(job.done)) / \(Fmt.bytes(job.total))")
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)

                        Spacer()

                        Text("\(Int(job.fraction * 100))%")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(pillColor)
                    }
                }

                if job.isActive {
                    HStack(spacing: 10) {
                        Spacer()

                        if job.status == "paused" {
                            Button {
                                Task { try? await api.resumeJob(job.id); onChange() }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "play.fill").font(.caption2)
                                    Text("Resume").font(.caption2).fontWeight(.semibold)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Theme.green.opacity(0.2), in: Capsule())
                                .foregroundStyle(Theme.green)
                            }
                            .buttonStyle(BouncyButtonStyle())
                        } else {
                            Button {
                                Task { try? await api.pauseJob(job.id); onChange() }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "pause.fill").font(.caption2)
                                    Text("Pause").font(.caption2).fontWeight(.semibold)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Theme.warn.opacity(0.2), in: Capsule())
                                .foregroundStyle(Theme.warn)
                            }
                            .buttonStyle(BouncyButtonStyle())
                        }

                        Button(role: .destructive) {
                            Task { try? await api.cancelJob(job.id); onChange() }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "xmark").font(.caption2)
                                Text("Cancel").font(.caption2).fontWeight(.semibold)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Theme.red.opacity(0.2), in: Capsule())
                            .foregroundStyle(Theme.red)
                        }
                        .buttonStyle(BouncyButtonStyle())
                    }
                }

                if !job.error.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                        Text(job.error)
                            .font(.caption2)
                    }
                    .foregroundStyle(Theme.red)
                }
            }
            .padding(14)
        }
    }

    private var fileIcon: String {
        let name = job.name.lowercased()
        if name.hasSuffix(".mp4") || name.hasSuffix(".mov") || name.hasSuffix(".mkv") {
            return "film"
        } else if name.hasSuffix(".jpg") || name.hasSuffix(".jpeg") || name.hasSuffix(".png") {
            return "photo"
        } else if name.hasSuffix(".mp3") || name.hasSuffix(".m4a") {
            return "waveform"
        }
        return "arrow.up.doc"
    }

    private var pillColor: Color {
        switch job.status {
        case "uploading": return Theme.telegramSky
        case "done": return Theme.green
        case "error", "cancelled": return Theme.red
        case "paused": return Theme.warn
        default: return Theme.blue
        }
    }
}
