//
//  TangoViews.swift — watchlist, live check, recordings + download.
//

import SwiftUI

struct TangoRootView: View {
    let api: TangoAPI
    @State private var section = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $section) {
                Text("Watchlist").tag(0)
                Text("Recordings").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            if section == 0 {
                TangoWatchlistView(api: api)
            } else {
                TangoRecordingsView(api: api)
            }
        }
        .background(AppBackground())
    }
}

// MARK: - Watchlist

private struct TangoWatchlistView: View {
    let api: TangoAPI

    @State private var items: [TangoStreamer] = []
    @State private var errorText: String?
    @State private var showAdd = false
    @State private var logHandle: String?
    @State private var checking = false

    var body: some View {
        content
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        Task { await check() }
                    } label: {
                        if checking {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                        }
                    }
                    .disabled(checking)
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .refreshable { await load() }
            .task {
                while !Task.isCancelled {
                    await load()
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                }
            }
            .sheet(isPresented: $showAdd, onDismiss: { Task { await load() } }) {
                TangoAddSheet(api: api)
            }
            .sheet(item: Binding(
                get: { logHandle.map(TangoLogTarget.init(handle:)) },
                set: { logHandle = $0?.handle }
            )) { target in
                TangoLogSheet(api: api, handle: target.handle)
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
                            SecondaryLabel("Watchlist empty — tap + to add a streamer.")
                                .frame(maxWidth: .infinity)
                                .padding(24)
                        }
                    } else {
                        ForEach(items) { s in
                            TangoStreamerCard(api: api, streamer: s,
                                              onLog: { logHandle = s.handle },
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
            items = try await api.streamers()
            errorText = nil
        } catch {
            errorText = error.messageText
        }
    }

    private func check() async {
        checking = true
        defer { checking = false }
        _ = try? await api.check()
        await load()
    }
}

private struct TangoLogTarget: Identifiable {
    let handle: String
    var id: String { handle }
}

private struct TangoStreamerCard: View {
    let api: TangoAPI
    let streamer: TangoStreamer
    let onLog: () -> Void
    let onChange: () -> Void
    @State private var confirm = false

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.title)
                        .foregroundStyle(streamer.isLive ? Theme.red : Theme.textSecondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(streamer.handle)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.textPrimary)
                        if streamer.isRecording {
                            SecondaryLabel(
                                "\(streamer.segments) segments · \(Fmt.duration(Double(streamer.seconds)))",
                                font: .caption2)
                        } else {
                            SecondaryLabel(streamer.status, font: .caption2)
                        }
                    }
                    Spacer()
                    StatusPill(text: streamer.status, color: pillColor)
                }

                HStack(spacing: 8) {
                    if streamer.isRecording {
                        Button("Stop") {
                            Task {
                                try? await api.stop(streamer.handle)
                                onChange()
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(Theme.red)
                    } else {
                        Button("Record") {
                            Task {
                                try? await api.record(streamer.handle)
                                onChange()
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(Theme.red)
                    }
                    Button { onLog() } label: {
                        Image(systemName: "doc.text")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Button(role: .destructive) { confirm = true } label: {
                        Image(systemName: "trash").font(.caption)
                    }
                    .tint(.red)
                }
            }
            .padding(14)
        }
        .confirmationDialog("Remove \(streamer.handle)?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                Task {
                    try? await api.removeStreamer(streamer.handle)
                    onChange()
                }
            }
        }
    }

    private var pillColor: Color {
        switch streamer.status {
        case "recording", "starting": return Theme.red
        case "live": return Theme.green
        case "error": return Theme.warn
        default: return Theme.textSecondary
        }
    }
}

private struct TangoAddSheet: View {
    let api: TangoAPI
    @Environment(\.dismiss) private var dismiss

    @State private var handle = ""
    @State private var recordNow = true
    @State private var busy = false
    @State private var err: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Tango streamer") {
                    TextField("handle or tango.me link", text: $handle)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Toggle("Start recording now", isOn: $recordNow)
                }
                if let err {
                    Section { Text(err).foregroundStyle(.red).font(.caption) }
                }
            }
            .navigationTitle("Add streamer")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { Task { await add() } }
                        .disabled(busy || handle.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func add() async {
        busy = true
        defer { busy = false }
        let clean = handle.trimmingCharacters(in: .whitespaces)
            .split(separator: "/").last.map(String.init) ?? ""
        let bare = clean.split(separator: "?").first.map(String.init) ?? clean
        do {
            try await api.addStreamer(bare)
            if recordNow { try? await api.record(bare) }
            dismiss()
        } catch {
            err = error.messageText
        }
    }
}

private struct TangoLogSheet: View {
    let api: TangoAPI
    let handle: String
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
            .navigationTitle("\(handle) log")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                lines = (try? await api.log(handle: handle)) ?? []
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Recordings

private struct TangoRecordingsView: View {
    let api: TangoAPI

    @State private var items: [TangoRecording] = []
    @State private var errorText: String?
    @State private var shareTarget: TangoShareTarget?
    @State private var busyName: String?

    var body: some View {
        content
            .refreshable { await load() }
            .task {
                while !Task.isCancelled {
                    await load()
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                }
            }
            .sheet(item: $shareTarget) { target in
                ShareSheet(url: target.url)
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
                            SecondaryLabel("No MP4s yet.")
                                .frame(maxWidth: .infinity)
                                .padding(24)
                        }
                    } else {
                        ForEach(items) { r in
                            GlassCard {
                                HStack(spacing: 12) {
                                    TangoThumb(api: api, rec: r)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(r.name)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundStyle(Theme.textPrimary)
                                            .lineLimit(1)
                                        SecondaryLabel(
                                            "\(Fmt.bytes(r.size)) · \(Fmt.date(r.mtime))",
                                            font: .caption2)
                                    }
                                    Spacer()
                                    if busyName == r.name {
                                        ProgressView().tint(.white)
                                    } else {
                                        Button {
                                            Task { await download(r) }
                                        } label: {
                                            Image(systemName: "square.and.arrow.down")
                                                .foregroundStyle(Theme.blue)
                                        }
                                    }
                                }
                                .padding(12)
                            }
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
            items = try await api.recordings()
            errorText = nil
        } catch {
            errorText = error.messageText
        }
    }

    private func download(_ rec: TangoRecording) async {
        busyName = rec.name
        defer { busyName = nil }
        if let url = try? await api.downloadToTemp(rec) {
            shareTarget = TangoShareTarget(url: url)
        }
    }
}

private struct TangoShareTarget: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

private struct TangoThumb: View {
    let api: TangoAPI
    let rec: TangoRecording
    @State private var data: Data?

    var body: some View {
        Group {
            if let data, let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .overlay {
                        Image(systemName: "film")
                            .foregroundStyle(Theme.textSecondary)
                    }
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .task {
            guard data == nil else { return }
            data = try? await api.thumbData(rec)
        }
    }
}
