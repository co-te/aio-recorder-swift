//
//  LogsView.swift — server event log.
//

import SwiftUI

struct DriveLogsView: View {
    let api: DriveAPI

    @State private var entries: [TDLogEntry] = []
    @State private var errorText: String?
    @State private var filter = ""

    var body: some View {
        content
            .background(AppBackground())
            .navigationTitle("Logs")
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
        if let err = errorText, entries.isEmpty {
            ErrorStateView(message: err) { Task { await load() } }
        } else {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        DriveFilterChip(label: "All", active: filter.isEmpty) {
                            filter = ""
                        }
                        ForEach(["info", "warn", "error"], id: \.self) { level in
                            DriveFilterChip(label: level, active: filter == level) {
                                filter = filter == level ? "" : level
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
                ScrollView {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 3) {
                            if visible.isEmpty {
                                SecondaryLabel("No matching log lines.")
                            } else {
                                ForEach(visible) { e in
                                    HStack(alignment: .top, spacing: 8) {
                                        Text(Fmt.logTime(e.time))
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundStyle(Theme.textSecondary)
                                            .frame(width: 56, alignment: .leading)
                                        Text(e.message)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(color(for: e.level))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 16)
                    Spacer(minLength: 24)
                }
            }
        }
    }

    private var visible: [TDLogEntry] {
        let list = filter.isEmpty ? entries : entries.filter { $0.level == filter }
        return Array(list.reversed())
    }

    private func color(for level: String) -> Color {
        switch level {
        case "error": return Theme.red
        case "warn": return Theme.warn
        default: return Theme.textSecondary
        }
    }

    private func load() async {
        do {
            entries = try await api.logs()
            errorText = nil
        } catch {
            errorText = error.messageText
        }
    }

    private func loadQuiet() async {
        if let fresh = try? await api.logs() {
            if fresh.count != entries.count || fresh.last?.id != entries.last?.id {
                entries = fresh
            }
        }
    }
}

private struct DriveFilterChip: View {
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
        .background(active ? Theme.blue.opacity(0.3) : Color.white.opacity(0.06), in: Capsule())
        .foregroundStyle(active ? Theme.textPrimary : Theme.textSecondary)
    }
}
