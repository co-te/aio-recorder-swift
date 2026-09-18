//
//  DashboardView.swift — total points hero, live streamer cards (WS-driven).
//

import SwiftUI

struct DashboardView: View {
    let api: MinerAPI

    @State private var streamers: [StreamerState] = []
    @State private var running: Bool?
    @State private var errorText: String?

    private var totalPoints: Int { streamers.reduce(0) { $0 + $1.points } }
    private var online: [StreamerState] { streamers.filter { $0.isOnline } }

    var body: some View {
        content
            .background(AppBackground())
            .navigationTitle("Miner")
            .refreshable { await load() }
            .task {
                await load()
                for await list in api.stateStream() {
                    if !list.isEmpty {
                        streamers = list
                        errorText = nil
                    }
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if let err = errorText, streamers.isEmpty {
            ErrorStateView(message: err) { Task { await load() } }
        } else {
            ScrollView {
                VStack(spacing: 14) {
                    heroCard
                    statusCard
                    streamersCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
    }

    // MARK: hero

    private var heroCard: some View {
        GlassCard {
            VStack(spacing: 6) {
                Image(systemName: "diamond.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.gold)
                Text(Fmt.points(totalPoints))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                Text("total channel points")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                Text("\(streamers.count) channels · \(online.count) live")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
    }

    // MARK: status

    private var statusCard: some View {
        GlassCard {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill((running == true ? Theme.green : Theme.red).opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: running == true ? "play.fill" : "stop.fill")
                        .foregroundStyle(running == true ? Theme.green : Theme.red)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(running == true ? "Miner running" : "Miner offline")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.textPrimary)
                    SecondaryLabel("docker container ttv-ttv-1")
                }
                Spacer()
                GlassButton(title: "Refresh", icon: "arrow.clockwise", tint: Theme.blue) {
                    Task {
                        try? await api.refreshPoints()
                        await load()
                    }
                }
                GlassButton(title: "Restart", icon: "arrow.triangle.2.circlepath", tint: Theme.warn) {
                    Task {
                        try? await api.applyRestart()
                        try? await Task.sleep(nanoseconds: 8_000_000_000)
                        await load()
                    }
                }
            }
        }
    }

    // MARK: streamers

    @ViewBuilder
    private var streamersCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Channels", icon: "person.3.fill")
                if streamers.isEmpty {
                    SecondaryLabel("No channels being farmed.")
                } else {
                    ForEach(online) { s in
                        MinerRow(state: s)
                        if s.id != online.last?.id {
                            Divider().overlay(Theme.textSecondary.opacity(0.12))
                        }
                    }
                    if !offline.isEmpty {
                        CardHeader(title: "Offline", icon: "moon.zzz")
                        ForEach(offline) { s in
                            MinerRow(state: s)
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private var offline: [StreamerState] { streamers.filter { !$0.isOnline } }

    // MARK: data

    private func load() async {
        do {
            async let s = api.streamers()
            async let m = api.minerStatus()
            let (full, run) = try await (s, m)
            running = run
            let existingPFPs = Dictionary(streamers.map { ($0.username, $0.pfp) }, uniquingKeysWith: { _, last in last })
            // map full -> state so both paths share one render, preserving pfp
            streamers = full.map {
                StreamerState(username: $0.username, points: $0.points,
                              isOnline: $0.isOnline, stream: $0.stream,
                              pfp: existingPFPs[$0.username] ?? "")
            }
            errorText = nil
        } catch {
            errorText = error.messageText
        }
    }
}

// MARK: - Row

struct MinerRow: View {
    let state: StreamerState

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: state.pfp)) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                Circle().fill(Theme.twitch.opacity(0.25))
            }
            .frame(width: 38, height: 38)
            .clipShape(Circle())
            .overlay(
                Circle().strokeBorder(state.isOnline ? Theme.green : Color.clear, lineWidth: 2)
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(state.username)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.textPrimary)
                if state.isOnline, !state.title.isEmpty {
                    Text(state.title)
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                } else if state.isOnline {
                    Text("Live").font(.caption2).foregroundStyle(Theme.green)
                } else {
                    Text("Offline").font(.caption2).foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Fmt.points(state.points))
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(Theme.gold)
                    .contentTransition(.numericText())
                Text("points")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}
