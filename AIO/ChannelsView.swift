//
//  ChannelsView.swift — manage which channels the miner farms.
//

import SwiftUI

struct ChannelsView: View {
    let api: MinerAPI

    @State private var streamers: [StreamerFull] = []
    @State private var errorText: String?
    @State private var showAdd = false
    @State private var editing: StreamerFull?

    var body: some View {
        content
            .background(AppBackground())
            .navigationTitle("Channels")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .refreshable { await load() }
            .task { await load() }
            .polling(every: 60) { await load() }
            .sheet(isPresented: $showAdd, onDismiss: { Task { await load() } }) {
                AddChannelSheet(api: api)
            }
            .sheet(item: $editing, onDismiss: { Task { await load() } }) { s in
                BetSettingsSheet(api: api, streamer: s)
            }
    }

    @ViewBuilder
    private var content: some View {
        if let err = errorText, streamers.isEmpty {
            ErrorStateView(message: err) { Task { await load() } }
        } else {
            ScrollView {
                VStack(spacing: 12) {
                    if streamers.isEmpty {
                        GlassCard {
                            VStack(spacing: 8) {
                                Image(systemName: "person.badge.plus")
                                    .font(.largeTitle)
                                    .foregroundStyle(Theme.textSecondary)
                                SecondaryLabel("No channels — tap + to add one.")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(24)
                        }
                    } else {
                        ForEach(streamers, id: \.username) { s in
                            ChannelCard(api: api, streamer: s) {
                                Task { await load() }
                            } onEdit: {
                                editing = s
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
            streamers = try await api.streamers()
            errorText = nil
        } catch {
            errorText = error.messageText
        }
    }
}

// MARK: - Card

private struct ChannelCard: View {
    let api: MinerAPI
    let streamer: StreamerFull
    let onAction: () -> Void
    let onEdit: () -> Void
    @State private var confirm = false

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    AsyncImage(url: URL(string: "https://static-cdn.jtvnw.net/jtv_user_pictures/\(streamer.username.lowercased())-profile_image-70x70.png")) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        Circle().fill(Theme.twitch.opacity(0.25))
                    }
                    .frame(width: 38, height: 38)
                    .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(streamer.username)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.textPrimary)
                        HStack(spacing: 8) {
                            Label(Fmt.points(streamer.points), systemImage: "diamond.fill")
                                .foregroundStyle(Theme.gold)
                            if streamer.isOnline {
                                Label("live", systemImage: "record.circle")
                                    .foregroundStyle(Theme.green)
                            }
                        }
                        .font(.caption2)
                    }
                    Spacer()
                    Menu {
                        Button { onEdit() } label: {
                            Label("Bet settings", systemImage: "slider.horizontal.3")
                        }
                        Button(role: .destructive) { confirm = true } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 30, height: 30)
                    }
                }

                // quick feature toggles
                HStack(spacing: 8) {
                    FeatureChip(label: "Predict", on: streamer.settings.make_predictions, icon: "chart.bar")
                    FeatureChip(label: "Raids", on: streamer.settings.follow_raid, icon: "arrow.triangle.branch")
                    FeatureChip(label: "Drops", on: streamer.settings.claim_drops, icon: "gift")
                    FeatureChip(label: "Streak", on: streamer.settings.watch_streak, icon: "flame")
                }
            }
            .padding(16)
        }
        .confirmationDialog(
            "Remove \(streamer.username) from the miner?",
            isPresented: $confirm,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                Task {
                    try? await api.removeStreamer(streamer.username)
                    onAction()
                }
            }
        }
    }
}

private struct FeatureChip: View {
    let label: String
    let on: Bool
    let icon: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.caption2)
            Text(label).font(.caption2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background((on ? Theme.green : Theme.textSecondary).opacity(0.15))
        .foregroundStyle(on ? Theme.green : Theme.textSecondary)
        .clipShape(Capsule())
    }
}

// MARK: - Add sheet

struct AddChannelSheet: View {
    let api: MinerAPI
    @Environment(\.dismiss) private var dismiss

    @State private var username = ""
    @State private var busy = false
    @State private var err: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Twitch channel") {
                    TextField("username, e.g. aspen", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                if let err {
                    Section { Text(err).foregroundStyle(.red).font(.caption) }
                }
            }
            .navigationTitle("Add channel")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { Task { await add() } }
                        .disabled(busy || username.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func add() async {
        busy = true
        defer { busy = false }
        let clean = username.trimmingCharacters(in: .whitespaces)
        do {
            try await api.addStreamer(clean)
            toastLater()
            dismiss()
        } catch {
            err = error.messageText
        }
    }

    private func toastLater() {
        Task { @MainActor in
            NotificationCenter.default.post(name: .minerToast, object: "Added — restart miner to apply")
        }
    }
}

// MARK: - Bet settings sheet

struct BetSettingsSheet: View {
    let api: MinerAPI
    let streamer: StreamerFull
    @Environment(\.dismiss) private var dismiss

    @State private var settings: BetSettings
    @State private var busy = false
    @State private var err: String?

    init(api: MinerAPI, streamer: StreamerFull) {
        self.api = api
        self.streamer = streamer
        _settings = State(initialValue: streamer.settings)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Features") {
                    Toggle("Make predictions", isOn: $settings.make_predictions)
                    Toggle("Follow raids", isOn: $settings.follow_raid)
                    Toggle("Claim drops", isOn: $settings.claim_drops)
                    Toggle("Claim moments", isOn: $settings.claim_moments)
                    Toggle("Watch streak", isOn: $settings.watch_streak)
                    Toggle("Community goals", isOn: $settings.community_goals)
                }
                Section("Betting") {
                    Picker("Strategy", selection: $settings.bet.strategy) {
                        Text("SMART").tag("SMART")
                        Text("MOST_VOTED").tag("MOST_VOTED")
                        Text("HIGH_ODDS").tag("HIGH_ODDS")
                        Text("LOW_ODDS").tag("LOW_ODDS")
                        Text("STEALTH").tag("STEALTH")
                    }
                    Stepper("Bet \(settings.bet.percentage)% of points", value: $settings.bet.percentage, in: 1...100)
                    Stepper("Gap \(settings.bet.percentage_gap)%", value: $settings.bet.percentage_gap, in: 1...100)
                    Toggle("Stealth mode", isOn: $settings.bet.stealth_mode)
                    Stepper("Delay \(settings.bet.delay)s", value: $settings.bet.delay, in: 0...60)
                    Stepper("Min points \(settings.bet.minimum_points)", value: $settings.bet.minimum_points, in: 0...10_000_000, step: 1000)
                    Stepper("Max points \(settings.bet.max_points)", value: $settings.bet.max_points, in: 0...10_000_000, step: 1000)
                }
                Section("Filter") {
                    Picker("By", selection: $settings.bet.filter_condition.by) {
                        Text("Total users").tag("TOTAL_USERS")
                        Text("Odds").tag("ODDS")
                        Text("Points").tag("POINTS")
                    }
                    Picker("Where", selection: $settings.bet.filter_condition.`where`) {
                        Text("≤").tag("LTE")
                        Text("≥").tag("GTE")
                    }
                    Stepper("Value \(settings.bet.filter_condition.value)", value: $settings.bet.filter_condition.value, in: 0...100_000, step: 100)
                }
                if let err {
                    Section { Text(err).foregroundStyle(.red).font(.caption) }
                }
            }
            .navigationTitle("@\(streamer.username)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }.disabled(busy)
                }
            }
        }
    }

    private func save() async {
        busy = true
        defer { busy = false }
        do {
            try await api.updateStreamerSettings(streamer.username, settings)
            NotificationCenter.default.post(name: .minerToast, object: "Saved — restart miner to apply")
            dismiss()
        } catch {
            err = error.messageText
        }
    }
}
