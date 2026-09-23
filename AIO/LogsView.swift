//
//  LogsView.swift — miner log tail: virtualized list, background fetch.
//

import SwiftUI

/// One parsed log line. Miner lines look like
/// "2026-09-11 10:00:01,234 [INFO] message…" — parser is tolerant.
private struct MinerLogLine: Identifiable {
    let id: String
    let time: String
    let level: String
    let message: String

    var color: Color {
        switch level {
        case "ERROR", "CRITICAL": return Theme.red
        case "WARNING": return Theme.warn
        case "INFO": return Theme.textPrimary
        default: return Theme.textSecondary
        }
    }

    static func parse(_ raw: String) -> MinerLogLine {
        let lineId = UUID().uuidString
        // Split "…[LEVEL] message" tail first.
        if let open = raw.firstIndex(of: "["),
           let close = raw[open...].firstIndex(of: "]") {
            let lvl = String(raw[raw.index(after: open)..<close]).uppercased()
            let msg = String(raw[raw.index(after: close)...]).trimmingCharacters(in: .whitespaces)
            let t = String(raw[..<open]).trimmingCharacters(in: .whitespaces)
            return MinerLogLine(id: lineId, time: shortTime(t), level: lvl, message: msg)
        }
        return MinerLogLine(id: lineId, time: "", level: "", message: raw)
    }

    /// "2026-09-11 10:00:01,234" → "10:00:01".
    private static func shortTime(_ t: String) -> String {
        let parts = t.split(separator: " ")
        guard parts.count >= 2 else { return t }
        return String(parts[1].split(separator: ",").first ?? parts[1])
    }
}

struct LogsView: View {
    let api: MinerAPI

    @State private var all: [MinerLogLine] = []
    @State private var errorText: String?
    @State private var loading = false
    @State private var query = ""
    @State private var levelFilter = ""

    var body: some View {
        content
            .background(AppBackground())
            .searchable(text: $query, prompt: "Filter logs")
            .refreshable { await load() }
            .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if let err = errorText, all.isEmpty {
            ErrorStateView(message: err) { Task { await load() } }
        } else {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        FilterChip(label: "All", active: levelFilter.isEmpty) {
                            levelFilter = ""
                        }
                        ForEach(["ERROR", "WARNING", "INFO"], id: \.self) { lvl in
                            FilterChip(label: lvl.capitalized, active: levelFilter == lvl) {
                                levelFilter = levelFilter == lvl ? "" : lvl
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }

                if loading, all.isEmpty {
                    ProgressView().tint(.white).padding(.top, 40)
                    Spacer()
                } else if visible.isEmpty {
                    SecondaryLabel("No matching log lines.").padding(.top, 40)
                    Spacer()
                } else {
                    // List virtualizes rows — only visible ones are rendered.
                    List(visible) { line in
                        HStack(alignment: .top, spacing: 8) {
                            if !line.time.isEmpty {
                                Text(line.time)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(Theme.textSecondary)
                                    .frame(width: 56, alignment: .leading)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                if !line.level.isEmpty {
                                    Text(line.level)
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .foregroundStyle(line.color)
                                }
                                Text(line.message)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.textPrimary)
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(.vertical, 3)
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(Color.white.opacity(0.07))
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
        }
    }

    private var visible: [MinerLogLine] {
        // Newest first, capped so the list stays light.
        let base = all.reversed()
        let byLevel = levelFilter.isEmpty ? Array(base) : base.filter { $0.level == levelFilter }
        guard !query.isEmpty else { return Array(byLevel.prefix(200)) }
        return Array(byLevel.filter { $0.message.localizedCaseInsensitiveContains(query) }.prefix(200))
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            // Decode off the main actor — the payload can be large.
            let raw = try await Task.detached(priority: .userInitiated) {
                try await api.recentLogs(lines: 150)
            }.value
            let parsed = raw.map { MinerLogLine.parse($0) }
            await MainActor.run {
                all = parsed
                errorText = nil
            }
        } catch {
            await MainActor.run { errorText = error.messageText }
        }
    }
}

private struct FilterChip: View {
    let label: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .fontWeight(active ? .bold : .regular)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
        }
        .background(active ? Theme.twitch.opacity(0.3) : Color.white.opacity(0.06))
        .foregroundStyle(active ? Theme.textPrimary : Theme.textSecondary)
        .clipShape(Capsule())
    }
}
