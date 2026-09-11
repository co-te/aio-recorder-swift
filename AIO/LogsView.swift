//
//  LogsView.swift — miner log tail with streamer filter.
//

import SwiftUI

struct LogsView: View {
    let api: MinerAPI

    @State private var lines: [String] = []
    @State private var errorText: String?
    @State private var filter = ""

    var body: some View {
        content
            .background(AppBackground())
            .navigationTitle("Logs")
            .refreshable { await load() }
            .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if let err = errorText, lines.isEmpty {
            ErrorStateView(message: err) { Task { await load() } }
        } else {
            VStack(spacing: 0) {
                // filter chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        FilterChip(label: "All", active: filter.isEmpty) {
                            filter = ""
                            Task { await load() }
                        }
                        ForEach(["error", "bet", "points", "claim"], id: \.self) { kw in
                            FilterChip(label: kw, active: filter == kw) {
                                filter = filter == kw ? "" : kw
                                Task { await load() }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
                GlassCard {
                    VStack(alignment: .leading, spacing: 2) {
                        if visibleLines.isEmpty {
                            SecondaryLabel("No matching log lines.")
                        } else {
                            ForEach(Array(visibleLines.enumerated()), id: \.offset) { _, line in
                                LogLineView(line: line)
                            }
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 16)
                Spacer()
            }
        }
    }

    private var visibleLines: [String] {
        filter.isEmpty ? lines : lines.filter { $0.localizedCaseInsensitiveContains(filter) }
    }

    private func load() async {
        do {
            lines = try await api.recentLogs(lines: 120)
            errorText = nil
        } catch {
            errorText = error.messageText
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

private struct LogLineView: View {
    let line: String

    private var color: Color {
        let l = line.lowercased()
        if l.contains("error") || l.contains("fail") { return Theme.red }
        if l.contains("warn") { return Theme.warn }
        if l.contains("set_online") || l.contains("claim") { return Theme.green }
        if l.contains("bet") || l.contains("prediction") { return Theme.twitch }
        return Theme.textSecondary
    }

    var body: some View {
        Text(line)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
