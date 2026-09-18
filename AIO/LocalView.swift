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
    @State private var selection = Set<String>()
    @State private var batchBusy = false
    @State private var batchDone = 0
    @State private var skipDupes = true

    private var files: [TDLocalEntry] { entries.filter { !$0.isDir } }
    private var allSelected: Bool { !files.isEmpty && selection.isSuperset(of: files.map(\.path)) }

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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(allSelected ? "Clear" : "Select all") {
                        if allSelected {
                            selection.removeAll()
                        } else {
                            selection.formUnion(files.map(\.path))
                        }
                    }
                    .disabled(files.isEmpty)
                }
            }
            .refreshable { await load() }
            .task {
                folders = (try? await api.folders()) ?? []
                if target == nil { target = folders.first }
                while !Task.isCancelled {
                    await load()
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                }
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
                                LocalRow(entry: e, selected: selection.contains(e.path)) {
                                    if e.isDir {
                                        path = e.path
                                        selection.removeAll()
                                        Task { await load() }
                                    } else {
                                        if selection.contains(e.path) {
                                            selection.remove(e.path)
                                        } else {
                                            selection.insert(e.path)
                                        }
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

                if !selection.isEmpty {
                    GlassCard {
                        VStack(spacing: 8) {
                            HStack {
                                SecondaryLabel("\(selection.count) selected", font: .caption)
                                Spacer()
                                if batchBusy {
                                    ProgressView().tint(.white)
                                    SecondaryLabel("\(batchDone)/\(selection.count)", font: .caption2)
                                } else {
                                    Button("Upload all") {
                                        Task { await pushSelected() }
                                    }
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(Theme.blue.opacity(0.3), in: Capsule())
                                    .foregroundStyle(Theme.textPrimary)
                                }
                            }
                            Toggle("Skip already-uploaded files", isOn: $skipDupes)
                                .font(.caption)
                                .tint(Theme.blue)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .padding(12)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
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
            selection.formIntersection(entries.map(\.path))
        } catch {
            errorText = error.messageText
        }
    }

    private func pushSelected() async {
        guard let dest = target, !selection.isEmpty else { return }
        batchBusy = true
        batchDone = 0
        defer { batchBusy = false }
        var paths = files.filter { selection.contains($0.path) }
        var skipped = 0
        if skipDupes, !paths.isEmpty {
            let existing = await existingKeys(peerType: dest.peerType, peerId: dest.peerId)
            paths = paths.filter { entry in
                let dupe = existing.contains("\(entry.name)|\(entry.size)")
                if dupe { skipped += 1 }
                return !dupe
            }
        }
        var failed = 0
        for entry in paths {
            do {
                try await api.localUpload(path: entry.path, peerType: dest.peerType, peerId: dest.peerId)
            } catch {
                failed += 1
            }
            batchDone += 1
        }
        selection.removeAll()
        var parts: [String] = []
        if !paths.isEmpty { parts.append("Queued \(paths.count - failed)/\(paths.count)") }
        if skipped > 0 { parts.append("skipped \(skipped) dupes") }
        if failed > 0 { parts.append("\(failed) failed") }
        note = (parts.isEmpty ? "Nothing to upload" : parts.joined(separator: ", ")) + " → \(dest.name)"
    }

    /// name|size keys of everything already in the folder (paged, capped).
    private func existingKeys(peerType: String, peerId: Int) async -> Set<String> {
        var keys = Set<String>()
        var offset = 0
        for _ in 0..<20 {
            guard let (items, next) = try? await api.files(
                peerType: peerType, peerId: peerId, offsetId: offset) else { break }
            for f in items { keys.insert("\(f.name)|\(f.size)") }
            if next <= 0 { break }
            offset = next
        }
        return keys
    }
}

// MARK: - Row (names always visible — no blank rows)

private struct LocalRow: View {
    let entry: TDLocalEntry
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            GlassCard {
                HStack(spacing: 12) {
                    if !entry.isDir {
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selected ? Theme.blue : Theme.textSecondary)
                            .frame(width: 24)
                    }
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
                    if entry.isDir {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(12)
            }
        }
        .buttonStyle(.plain)
    }
}
