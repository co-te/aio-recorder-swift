//
//  ViewsView.swift — smart views (favorites, pinned, offline, large, old, dupes, groups).
//

import SwiftUI

struct ViewsView: View {
    let api: DriveAPI

    private let views: [(key: String, label: String, icon: String)] = [
        ("favorites", "Favorites", "star.fill"),
        ("pinned", "Pinned", "pin.fill"),
        ("offline", "Offline", "arrow.down.circle.fill"),
        ("large", "Large files", "cylinder.fill"),
        ("old", "Oldest", "clock.fill"),
        ("dupes", "Duplicates", "square.on.square"),
        ("unassigned", "Ungrouped", "tag.slash"),
        ("group", "Grouped", "tag.fill"),
    ]

    @State private var selected = "favorites"
    @State private var groupFilter = ""
    @State private var groups: [String] = []
    @State private var items: [TDFile] = []
    @State private var loading = false
    @State private var errorText: String?
    @State private var detail: TDFile?
    @State private var showCreateGroup = false
    @State private var newGroupName = ""

    var body: some View {
        content
            .background(AppBackground())
            .navigationTitle("Views")
            .refreshable { await load() }
            .task {
                groups = (try? await api.groups()) ?? []
                await load()
            }
            .sheet(item: $detail) { f in
                FileDetailSheet(api: api, file: f)
            }
            .sheet(isPresented: $showCreateGroup) {
                NavigationStack {
                    Form {
                        Section("Group name") {
                            TextField("e.g. movies", text: $newGroupName)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                    }
                    .navigationTitle("New group")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showCreateGroup = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Create") {
                                Task { await createGroup() }
                            }
                            .disabled(newGroupName.isEmpty)
                        }
                    }
                }
                .presentationDetents([.medium])
            }
    }

    @ViewBuilder
    private var content: some View {
        if let err = errorText, items.isEmpty {
            ErrorStateView(message: err) { Task { await load() } }
        } else {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(views, id: \.key) { v in
                            Button {
                                selected = v.key
                                Task { await load() }
                            } label: {
                                Label(v.label, systemImage: v.icon)
                                    .font(.caption)
                                    .fontWeight(selected == v.key ? .bold : .regular)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                            }
                            .background(
                                selected == v.key
                                    ? Theme.blue.opacity(0.3)
                                    : Color.white.opacity(0.06),
                                in: Capsule()
                            )
                            .foregroundStyle(selected == v.key ? Theme.textPrimary : Theme.textSecondary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }

                if selected == "group" {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            Button {
                                showCreateGroup = true
                            } label: {
                                Label("New", systemImage: "plus")
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                            }
                            .background(Theme.blue.opacity(0.25), in: Capsule())
                            .foregroundStyle(Theme.textPrimary)
                            Button {
                                groupFilter = ""
                                Task { await load() }
                            } label: {
                                Text("All")
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                            }
                            .background(
                                groupFilter.isEmpty ? Theme.gold.opacity(0.3) : Color.white.opacity(0.06),
                                in: Capsule()
                            )
                            .foregroundStyle(Theme.textPrimary)
                            ForEach(groups, id: \.self) { g in
                                Button {
                                    groupFilter = g
                                    Task { await load() }
                                } label: {
                                    Text(g)
                                        .font(.caption)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                }
                                .background(
                                    groupFilter == g ? Theme.gold.opacity(0.3) : Color.white.opacity(0.06),
                                    in: Capsule()
                                )
                                .foregroundStyle(Theme.textPrimary)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                    }
                }

                ScrollView {
                    VStack(spacing: 10) {
                        if loading, items.isEmpty {
                            ProgressView().tint(.white).padding(.top, 40)
                        } else if items.isEmpty {
                            GlassCard {
                                SecondaryLabel("Nothing in this view.")
                                    .frame(maxWidth: .infinity)
                                    .padding(24)
                            }
                            .padding(.horizontal, 16)
                        } else {
                            SecondaryLabel("\(items.count) items", font: .caption2)
                            ForEach(items, id: \.rowId) { f in
                                Button { detail = f } label: {
                                    GlassCard { FileRow(api: api, file: f) }
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                    .padding(.top, 6)
                    .padding(.bottom, 24)
                }
            }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            groups = (try? await api.groups()) ?? []
            items = try await api.view(
                selected,
                group: selected == "group" && !groupFilter.isEmpty ? groupFilter : nil)
            errorText = nil
        } catch {
            errorText = error.messageText
        }
    }

    private func createGroup() async {
        do {
            groups = try await api.createGroup(newGroupName.trimmingCharacters(in: .whitespaces))
            newGroupName = ""
            showCreateGroup = false
        } catch {
            errorText = error.messageText
            showCreateGroup = false
        }
    }
}
