//
//  SettingsView.swift — backend, quota, upload settings, sync/logout.
//

import SwiftUI

struct DriveSettingsView: View {
    @Binding var settings: DriveSettings
    let onApplied: (DriveSettings) -> Void

    @State private var host = ""
    @State private var port = ""
    @State private var token = ""
    @State private var maxConcurrent = 2
    @State private var usage: TDUsage?
    @State private var testing = false
    @State private var testResult: String?
    @State private var testOk = false
    @State private var confirmLogout = false

    private var api: DriveAPI { DriveAPI(settings: current()) }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        CardHeader(title: "Backend", icon: "server.rack")
                        GlassField(icon: "wifi", placeholder: "Pi IP address", text: $host, keyboard: .decimalPad)
                        GlassField(icon: "number", placeholder: "Port", text: $port, keyboard: .numberPad)
                        GlassField(icon: "key.fill", placeholder: "API token", text: $token, secure: true)
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        CardHeader(title: "Connection", icon: "bolt.horizontal")
                        HStack {
                            GlassButton(title: "Test", icon: "dot.radiowaves.left.and.right", tint: Theme.blue) {
                                Task { await test() }
                            }
                            .disabled(testing)
                            if testing { ProgressView().tint(.white) }
                            Spacer()
                        }
                        if let testResult {
                            Label(testResult, systemImage: testOk ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(testOk ? Theme.green : Theme.red)
                        }
                    }
                }

                if let usage {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            CardHeader(title: "Daily quota", icon: "gauge.with.dots.needle.67percent")
                            ProgressView(value: usage.fractionUsed)
                                .tint(usage.fractionUsed > 0.9 ? Theme.red : Theme.blue)
                            SecondaryLabel(
                                "\(Fmt.bytes(usage.uploadedBytes)) of \(Fmt.bytes(usage.limitBytes)) used · \(Fmt.bytes(usage.remainingBytes)) left",
                                font: .caption)
                            HStack {
                                GlassButton(title: "Reset", icon: "arrow.counterclockwise", tint: Theme.warn) {
                                    Task {
                                        try? await api.resetUsage()
                                        await loadUsage()
                                    }
                                }
                                Spacer()
                            }
                        }
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        CardHeader(title: "Uploads", icon: "cloud.upload")
                        Stepper("Max concurrent: \(maxConcurrent)", value: $maxConcurrent, in: 1...8)
                            .foregroundStyle(Theme.textPrimary)
                            .onChange(of: maxConcurrent) { n in
                                Task { try? await api.saveMaxConcurrent(n) }
                            }
                        HStack(spacing: 10) {
                            GlassButton(title: "Sync", icon: "arrow.triangle.2.circlepath", tint: Theme.green) {
                                Task { try? await api.sync() }
                            }
                            GlassButton(title: "Logout", icon: "rectangle.portrait.and.arrow.right", tint: Theme.red) {
                                confirmLogout = true
                            }
                        }
                    }
                }

                GlassButton(title: "Save", icon: "checkmark", tint: Theme.blue, prominent: true) {
                    apply()
                }
                .frame(maxWidth: .infinity)

                SecondaryLabel("Token never leaves this phone.", font: .caption2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(AppBackground())
        .navigationTitle("Settings")
        .refreshable {
            await loadUsage()
            await loadMaxConcurrent()
        }
        .task {
            await loadUsage()
            await loadMaxConcurrent()
        }
        .onAppear { fill() }
        .confirmationDialog("Log out of Telegram on the server?", isPresented: $confirmLogout) {
            Button("Logout", role: .destructive) {
                Task { try? await api.logout() }
            }
        }
    }

    private func fill() {
        host = settings.host
        port = String(settings.port)
        token = settings.token
    }

    private func current() -> DriveSettings {
        let h = host.trimmingCharacters(in: .whitespaces)
        return DriveSettings(
            host: h.isEmpty ? settings.host : h,
            port: Int(port) ?? settings.port,
            token: token)
    }

    private func test() async {
        testing = true
        defer { testing = false }
        do {
            let ok = try await api.checkAuth()
            testResult = ok ? "Connected — authenticated" : "Connected — token rejected"
            testOk = ok
        } catch {
            testResult = error.messageText
            testOk = false
        }
    }

    private func loadUsage() async {
        usage = try? await api.usage()
    }

    private func loadMaxConcurrent() async {
        if let n = try? await api.maxConcurrent() { maxConcurrent = n }
    }

    private func apply() {
        let s = current()
        s.save()
        onApplied(s)
    }
}
