//
//  ArchiverView.swift — recording-archiver script progress (tango/tik -> drive).
//

import SwiftUI

struct ArchiverActive: Decodable {
    var running: Bool = false
    var started: String = ""
    var total: Int = 0
    var queued: Int = 0
    var uploaded: Int = 0
    var skipped: Int = 0
    var current: String = ""
}

struct ArchiverDay: Decodable, Identifiable {
    var date: String = ""
    var runs: Int = 0
    var uploaded: Int = 0
    var deleted: Int = 0
    var skipped: Int = 0
    var id: String { date }
}

struct ArchiverStatus: Decodable {
    var active: ArchiverActive = ArchiverActive()
    var history: [ArchiverDay] = []
    var updated: String = ""
}

struct ArchiverView: View {
    let api: DriveAPI

    @State private var status: ArchiverStatus?
    @State private var errorText: String?
    @State private var pollTimer: Timer?
    @State private var runNote: String?
    @State private var runBusy = false

    var body: some View {
        content
            .background(AppBackground())
            .navigationTitle("Archiver")
            .refreshable { await load() }
            .task {
                await load()
                startPoll()
            }
            .onDisappear { stopPoll() }
    }

    private func startPoll() {
        stopPoll()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            Task { await loadQuiet() }
        }
    }

    private func stopPoll() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    @ViewBuilder
    private var content: some View {
        if let err = errorText, status == nil {
            ErrorStateView(message: err) { Task { await load() } }
        } else {
            ScrollView {
                VStack(spacing: 12) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            CardHeader(title: "Manual run", icon: "play.circle")
                            Button {
                                Task { await runNow() }
                            } label: {
                                Label(runBusy ? "Requesting…" : "Run archiver now",
                                      systemImage: "bolt.fill")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Theme.blue.opacity(0.25), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .foregroundStyle(Theme.textPrimary)
                            }
                            .disabled(runBusy)
                            if let runNote {
                                SecondaryLabel(runNote, font: .caption)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    if let a = status?.active {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 10) {
                                CardHeader(title: a.running ? "Archiving…" : "Idle",
                                           icon: a.running ? "arrow.triangle.2.circlepath" : "checkmark.circle")
                                if a.total > 0 {
                                    ProgressView(value: Double(a.uploaded + a.skipped),
                                                 total: Double(max(a.total, 1)))
                                        .tint(Theme.blue)
                                    SecondaryLabel("Uploaded \(a.uploaded)/\(a.total) · skipped \(a.skipped)")
                                } else {
                                    SecondaryLabel("No active job")
                                }
                                if !a.current.isEmpty, a.running {
                                    SecondaryLabel(a.current, font: .caption2)
                                        .lineLimit(1)
                                }
                                if !a.started.isEmpty {
                                    SecondaryLabel("Started \(a.started)", font: .caption2)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    let days = (status?.history ?? []).reversed()
                    if !days.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            SecondaryLabel("HISTORY", font: .caption2)
                                .padding(.horizontal, 20)
                            ForEach(Array(days)) { d in
                                GlassCard {
                                    VStack(alignment: .leading, spacing: 6) {
                                        CardHeader(title: d.date, icon: "calendar")
                                        SecondaryLabel(
                                            "Uploaded \(d.uploaded)/\(d.uploaded + d.skipped) successfully · deleted \(d.deleted) · \(d.runs) run\(d.runs == 1 ? "" : "s")"
                                        )
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                    }
                    if let u = status?.updated, !u.isEmpty {
                        SecondaryLabel("Updated \(u)", font: .caption2)
                    }
                }
                .padding(.vertical, 12)
            }
        }
    }

    private func load() async {
        do {
            status = try await api.archiverStatus()
            errorText = nil
        } catch {
            errorText = error.messageText
        }
    }

    private func loadQuiet() async {
        if let s = try? await api.archiverStatus() {
            status = s
            errorText = nil
        }
    }

    private func runNow() async {
        runBusy = true
        defer { runBusy = false }
        do {
            let state = try await api.archiverRun()
            runNote = state == "already-requested" ? "Run already requested" : "Run requested — starting shortly"
        } catch {
            runNote = "Request failed: \(error.messageText)"
        }
    }
}
