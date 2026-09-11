//
//  LocalView.swift — browse the Pi's local drive, push files to Telegram.
//

import SwiftUI

struct LocalView: View {
    let api: DriveAPI

    @State private var root = ""
    @State private var path = ""
    @State private var entries: [TDLocalEntry] = []
    @State private var folders: [TDFolder] = []
    @State private var target: TDFolder?
    @State private var loading = false
    @State private var errorText: String?
    @State private var note: String?

    private var crumbs: [(label: String, path: String)] {
        var out = [(label: "Root", path: "")]
        guard !path.isEmpty else { return out }
        var acc = ""
        for part in path.split(separator: "/").map(String.init) {
            acc = acc.isEmpty ? part : "\(acc)/\(part)"
            out.append((label: part, path: acc))
        }
        return out
    }

    var body: some View {
        content
            .background(AppBackground())
            .navigationTitle("Local drive")
            .refreshable { await load() }
            .task {
                await load()
                folders = (try? await api.folders()) ?? []
                if target == nil { target = folders.first }
            }
    }

    @ViewBuilder
    private var content: some View {
        if let err = errorText, entries.isEmpty {
            ErrorStateView(message: err) { Task { await load() } }
        } else {
            VStack(spacing: 0) {
                // breadcrumbs
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(crumbs.enumerated()), id: \.offset) { _, c in
                            Button {
                                path = c.path
                                Task { await load() }
                            } label: {
                                Text(c.label)
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                            }
                            .background(Color.white.opacity(0.07), in: Capsule())
                            .foregroundStyle(Theme.textSecondary)
                            if c.path != crumbs.last?.path {
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }

                // upload target
                HStack {
                    SecondaryLabel("Send to:", font: .caption)
                    Picker("Folder", selection: Binding(
                        get: { target?.id ?? "" },
                        set: { id in target = folders.first(where: { $0.id == id }) }
                    )) {
                        ForEach(folders) { f in Text(f.name).tag(f.id) }
                    }
                    .tint(Theme.blue)
                    .labelsHidden()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 6)

                ScrollView {
                    VStack(spacing: 8) {
                        if loading, entries.isEmpty {
                            ProgressView().tint(.white).padding(.top, 40)
                        } else if entries.isEmpty {
                            GlassCard {
                                SecondaryLabel("Empty folder.")
                                    .frame(maxWidth: .infinity)
                                    .padding(24)
                            }
                            .padding(.horizontal, 16)
                        } else {
                            ForEach(entries) { e in
                                LocalRow(entry: e) {
                                    if e.isDir {
                                        path = e.path
                                        Task { await load() }
                                    } else {
                                        Task { await push(e) }
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                        if let note {
                            SecondaryLabel(note, font: .caption)
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let r = try await api.localList(path: path)
            root = r.root
            path = r.path
            entries = r.entries.sorted {
                if $0.isDir != $1.isDir { return $0.isDir }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            errorText = nil
        } catch {
            errorText = error.messageText
        }
    }

    private func push(_ entry: TDLocalEntry) async {
        guard let dest = target else { return }
        do {
            try await api.localUpload(path: entry.path, peerType: dest.peerType, peerId: dest.peerId)
            note = "Queued \(entry.name) → \(dest.name)"
        } catch {
            note = error.messageText
        }
    }
}

// MARK: - Row (names always visible — no blank rows)

private struct LocalRow: View {
    let entry: TDLocalEntry
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            GlassCard {
                HStack(spacing: 12) {
                    Image(systemName: entry.isDir ? "folder.fill" : "doc.fill")
                        .foregroundStyle(entry.isDir ? Theme.blue : Theme.textSecondary)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.name)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        if !entry.isDir {
                            SecondaryLabel(Fmt.bytes(entry.size), font: .caption2)
                        }
                    }
                    Spacer()
                    Image(systemName: entry.isDir ? "chevron.right" : "icloud.and.arrow.up")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(12)
            }
        }
        .buttonStyle(.plain)
    }
}
