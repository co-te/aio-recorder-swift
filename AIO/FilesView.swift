//
//  FilesView.swift — folders → paginated file list → detail sheet.
//

import SwiftUI
import AVKit

struct FilesView: View {
    let api: DriveAPI

    @State private var folders: [TDFolder] = []
    @State private var selected: TDFolder?
    @State private var files: [TDFile] = []
    @State private var nextOffset = 0
    @State private var hasMore = false
    @State private var loadingFiles = false
    @State private var errorText: String?
    @State private var showCreate = false
    @State private var detail: TDFile?

    var body: some View {
        content
            .background(AppBackground())
            .navigationTitle("Files")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showCreate = true } label: { Image(systemName: "folder.badge.plus") }
                }
            }
            .refreshable { await reload() }
            .task {
                await reload()
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    if !Task.isCancelled {
                        await pollFoldersQuiet()
                    }
                }
            }
            .sheet(isPresented: $showCreate, onDismiss: { Task { await loadFolders() } }) {
                CreateFolderSheet(api: api)
            }
            .sheet(item: $detail, onDismiss: { Task { await loadFiles(reset: true) } }) { f in
                FileDetailSheet(api: api, file: f)
            }
    }

    @ViewBuilder
    private var content: some View {
        if let err = errorText, folders.isEmpty {
            ErrorStateView(message: err) { Task { await reload() } }
        } else {
            VStack(spacing: 0) {
                folderStrip
                Divider().background(Color.white.opacity(0.08))
                fileList
            }
        }
    }

    // MARK: - Folder strip

    private var folderStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(folders) { f in
                    Button {
                        selected = f
                        Task { await loadFiles(reset: true) }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: f.kind == "saved" ? "bookmark.fill" : "megaphone.fill")
                                .font(.title3)
                            Text(f.name)
                                .font(.caption2)
                                .lineLimit(1)
                        }
                        .frame(width: 76)
                        .padding(.vertical, 10)
                    }
                    .background(
                        (selected?.id == f.id ? Theme.blue : Color.white.opacity(0.05))
                            .opacity(selected?.id == f.id ? 0.25 : 1),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .foregroundStyle(selected?.id == f.id ? Theme.textPrimary : Theme.textSecondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    // MARK: - File list

    private var fileList: some View {
        ScrollView {
            VStack(spacing: 10) {
                if loadingFiles, files.isEmpty {
                    ProgressView().tint(.white).padding(.top, 40)
                } else if files.isEmpty {
                    GlassCard {
                        SecondaryLabel(selected == nil
                            ? "No folders yet — tap + to create one."
                            : "Nothing here yet.")
                            .frame(maxWidth: .infinity)
                            .padding(24)
                    }
                    .padding(.horizontal, 16)
                } else {
                    ForEach(files, id: \.rowId) { f in
                        Button { detail = f } label: {
                            GlassCard { FileRow(api: api, file: f) }
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)

                    if hasMore {
                        Button {
                            Task { await loadFiles(reset: false) }
                        } label: {
                            if loadingFiles {
                                ProgressView().tint(.white)
                            } else {
                                Text("Load more")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                        .padding(.bottom, 8)
                    }
                }
            }
            .padding(.top, 10)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Loads

    private func reload() async {
        await loadFolders()
        if selected != nil { await loadFiles(reset: true) }
    }

    private func loadFolders() async {
        do {
            folders = try await api.folders()
            if selected == nil { selected = folders.first }
            errorText = nil
        } catch {
            errorText = error.messageText
        }
    }

    private func pollFoldersQuiet() async {
        if let f = try? await api.folders() {
            folders = f
            if selected == nil { selected = f.first }
        }
    }

    private func loadFiles(reset: Bool) async {
        guard let sel = selected else { return }
        loadingFiles = true
        defer { loadingFiles = false }
        do {
            let (items, next) = try await api.files(
                peerType: sel.peerType, peerId: sel.peerId,
                offsetId: reset ? 0 : nextOffset)
            files = reset ? items : files + items
            nextOffset = next
            hasMore = next > 0
            errorText = nil
        } catch {
            errorText = error.messageText
        }
    }
}

// MARK: - Create folder

private struct CreateFolderSheet: View {
    let api: DriveAPI
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var busy = false
    @State private var err: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("New Telegram channel folder") {
                    TextField("Folder name", text: $name)
                }
                if let err {
                    Section { Text(err).foregroundStyle(.red).font(.caption) }
                }
            }
            .navigationTitle("New folder")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { Task { await create() } }
                        .disabled(busy || name.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func create() async {
        busy = true
        defer { busy = false }
        do {
            try await api.createFolder(name.trimmingCharacters(in: .whitespaces))
            dismiss()
        } catch {
            err = error.messageText
        }
    }
}

// MARK: - Detail sheet

struct FileDetailSheet: View {
    let api: DriveAPI
    let file: TDFile
    @Environment(\.dismiss) private var dismiss

    @State private var favorite: Bool
    @State private var pinned: Bool
    @State private var offline: Bool
    @State private var group: String
    @State private var groups: [String] = []
    @State private var busy = false
    @State private var confirmDelete = false
    @State private var playerTarget: PlayerTarget?
    @State private var shareTarget: ShareTarget?
    @State private var textContent = ""
    @State private var showText = false
    @State private var err: String?

    init(api: DriveAPI, file: TDFile) {
        self.api = api
        self.file = file
        _favorite = State(initialValue: file.favorite)
        _pinned = State(initialValue: file.pinned)
        _offline = State(initialValue: file.offline)
        _group = State(initialValue: file.group ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    AuthedImage(api: api, file: file, size: 120)

                    VStack(spacing: 4) {
                        Text(file.name).font(.headline).foregroundStyle(Theme.textPrimary)
                            .multilineTextAlignment(.center)
                        SecondaryLabel("\(Fmt.bytes(file.size)) · \(Fmt.date(file.date))", font: .caption)
                    }

                    GlassCard {
                        VStack(spacing: 4) {
                            Toggle("Favorite", isOn: $favorite)
                            Toggle("Pinned", isOn: $pinned)
                            Toggle("Available offline", isOn: $offline)
                        }
                        .tint(Theme.blue)
                        .foregroundStyle(Theme.textPrimary)
                        .onChange(of: favorite) { flagFlag("favorite", $0) }
                        .onChange(of: pinned) { flagFlag("pin", $0) }
                        .onChange(of: offline) { flagFlag("offline", $0) }
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            CardHeader(title: "Group", icon: "tag")
                            Picker("Group", selection: $group) {
                                Text("None").tag("")
                                ForEach(groups, id: \.self) { Text($0).tag($0) }
                            }
                            .tint(Theme.blue)
                            .onChange(of: group) { assignGroup($0) }
                        }
                    }

                    HStack(spacing: 10) {
                        if file.type == "video" || file.type == "audio" {
                            GlassButton(title: "Play", icon: "play.fill", tint: Theme.blue) {
                                Task { await play() }
                            }
                        }
                        if file.type == "text" || file.type == "message" {
                            GlassButton(title: "Text", icon: "doc.text", tint: Theme.blue) {
                                Task { await openText() }
                            }
                        }
                        GlassButton(title: "Save", icon: "square.and.arrow.down", tint: Theme.green) {
                            Task { await save() }
                        }
                        .disabled(busy)
                    }

                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label("Delete from Telegram", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)

                    if let err {
                        Text(err).font(.caption).foregroundStyle(Theme.red)
                    }
                    if busy { ProgressView().tint(.white) }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(AppBackground())
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .task {
                groups = (try? await api.groups()) ?? []
            }
            .confirmationDialog("Delete this file from Telegram?", isPresented: $confirmDelete) {
                Button("Delete", role: .destructive) {
                    Task {
                        try? await api.deleteFile(file)
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showText) {
                TextEditSheet(api: api, file: file, initial: textContent)
            }
            .fullScreenCover(item: $playerTarget) { target in
                VideoPlayer(player: AVPlayer(url: target.url))
                    .ignoresSafeArea()
                    .overlay(alignment: .topLeading) {
                        Button { playerTarget = nil } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title).foregroundStyle(.white.opacity(0.8))
                        }
                        .padding()
                    }
            }
            .sheet(item: $shareTarget) { target in
                ShareSheet(url: target.url)
            }
        }
    }

    private func flagFlag(_ flag: String, _ value: Bool) {
        Task {
            do { try await api.toggleFlag(file, flag: flag, value: value) }
            catch { err = error.messageText }
        }
    }

    private func assignGroup(_ name: String) {
        Task {
            do { try await api.assignGroup(file, group: name.isEmpty ? nil : name) }
            catch { err = error.messageText }
        }
    }

    private func play() async {
        busy = true
        defer { busy = false }
        do { playerTarget = PlayerTarget(url: try await api.downloadToTemp(file)) }
        catch { err = error.messageText }
    }

    private func save() async {
        busy = true
        defer { busy = false }
        do { shareTarget = ShareTarget(url: try await api.downloadToTemp(file)) }
        catch { err = error.messageText }
    }

    private func openText() async {
        do {
            textContent = try await api.readText(file)
            showText = true
        } catch { err = error.messageText }
    }
}

// MARK: - Text editor

private struct TextEditSheet: View {
    let api: DriveAPI
    let file: TDFile
    @Environment(\.dismiss) private var dismiss
    @State var initial: String
    @State private var saved = false

    var body: some View {
        NavigationStack {
            TextEditor(text: $initial)
                .padding()
                .navigationTitle("Text")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { Task { await save() } }
                    }
                }
        }
    }

    private func save() async {
        do {
            try await api.writeText(file, content: initial)
            saved = true
            dismiss()
        } catch { /* keep open on failure */ }
    }
}

// MARK: - Identifiable URL wrappers (for sheet/fullScreenCover item:)

struct PlayerTarget: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct ShareTarget: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
