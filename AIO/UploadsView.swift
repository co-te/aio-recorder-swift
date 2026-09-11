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

    var body: some View {
        content
            .background(AppBackground())
            .navigationTitle("Uploads")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Pause all") { Task { try? await api.pauseAll(); await load() } }
                        Button("Resume all") { Task { try? await api.resumeAll(); await load() } }
                        Button("Cancel all", role: .destructive) {
                            Task { try? await api.cancelAll(); await load() }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .refreshable { await load() }
            .task {
                await load()
                folders = (try? await api.folders()) ?? []
                if target == nil { target = folders.first }
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
                VStack(spacing: 12) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            CardHeader(title: "Upload from phone", icon: "iphone")
                            Picker("To folder", selection: Binding(
                                get: { target?.id ?? "" },
                                set: { id in target = folders.first(where: { $0.id == id }) }
                            )) {
                                ForEach(folders) { f in
                                    Text(f.name).tag(f.id)
                                }
                            }
                            .tint(Theme.blue)
                            PhotosPicker(selection: $pickerItem, matching: .any(of: [.images, .videos])) {
                                Label(uploading ? "Uploading…" : "Pick photo or video",
                                      systemImage: "photo.badge.plus")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Theme.blue.opacity(0.25), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .foregroundStyle(Theme.textPrimary)
                            }
                            .disabled(uploading || target == nil)
                            if let uploadNote {
                                SecondaryLabel(uploadNote, font: .caption)
                            }
                        }
                    }
                    .padding(.horizontal, 16)

                    let active = jobs.filter(\.isActive)
                    let done = jobs.filter { !$0.isActive }
                    if !active.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            SecondaryLabel("ACTIVE (\(active.count))", font: .caption2)
                                .padding(.horizontal, 20)
                            ForEach(active) { j in
                                JobCard(api: api, job: j) { Task { await load() } }
                                    .padding(.horizontal, 16)
                            }
                        }
                    }
                    if !done.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            SecondaryLabel("RECENT", font: .caption2)
                                .padding(.horizontal, 20)
                            ForEach(done.prefix(20)) { j in
                                JobCard(api: api, job: j) { Task { await load() } }
                                    .padding(.horizontal, 16)
                            }
                        }
                    }
                    if jobs.isEmpty {
                        GlassCard {
                            SecondaryLabel("No upload jobs.")
                                .frame(maxWidth: .infinity)
                                .padding(20)
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, 24)
            }
        }
    }

    private func load() async {
        do {
            jobs = try await api.uploadJobs()
            errorText = nil
        } catch {
            errorText = error.messageText
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
            let name = item.itemIdentifier ?? "upload"
            let ext = (item.supportedContentTypes.first?.preferredFilenameExtension).map { ".\($0)" } ?? ""
            try await api.uploadFile(
                data: data,
                filename: "\(name)\(ext)",
                mime: item.supportedContentTypes.first?.preferredMIMEType ?? "application/octet-stream",
                peerType: dest.peerType, peerId: dest.peerId)
            uploadNote = "Queued — watch it above."
            await load()
        } catch {
            uploadNote = error.messageText
        }
    }
}

// MARK: - Job card

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
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(job.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    StatusPill(text: job.status, color: pillColor)
                }
                ProgressView(value: job.fraction)
                    .tint(pillColor)
                HStack {
                    SecondaryLabel("\(Fmt.bytes(job.done)) / \(Fmt.bytes(job.total))", font: .caption2)
                    Spacer()
                    if job.isActive {
                        if job.status == "paused" {
                            Button { Task { try? await api.resumeJob(job.id); onChange() } } label: {
                                Image(systemName: "play.fill")
                            }
                        } else {
                            Button { Task { try? await api.pauseJob(job.id); onChange() } } label: {
                                Image(systemName: "pause.fill")
                            }
                        }
                        Button(role: .destructive) {
                            Task { try? await api.cancelJob(job.id); onChange() }
                        } label: {
                            Image(systemName: "xmark")
                        }
                    }
                }
                .foregroundStyle(Theme.textSecondary)
                if !job.error.isEmpty {
                    Text(job.error).font(.caption2).foregroundStyle(Theme.red)
                }
            }
            .padding(14)
        }
    }

    private var pillColor: Color {
        switch job.status {
        case "done": return Theme.green
        case "error", "cancelled": return Theme.red
        case "paused": return Theme.warn
        default: return Theme.blue
        }
    }
}
