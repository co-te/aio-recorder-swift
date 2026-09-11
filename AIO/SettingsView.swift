//
//  SettingsView.swift — miner connection + global settings.
//

import SwiftUI

struct SettingsView: View {
    @Binding var settings: MinerSettings
    let onApplied: (MinerSettings) -> Void

    @State private var host = ""
    @State private var port = ""
    @State private var token = ""
    @State private var refresh = ""
    @State private var testing = false
    @State private var testResult: String?
    @State private var testOk = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        CardHeader(title: "Miner backend", icon: "server.rack")
                        GlassField(icon: "wifi", placeholder: "Pi IP address", text: $host, keyboard: .decimalPad)
                        GlassField(icon: "number", placeholder: "Port", text: $port, keyboard: .numberPad)
                        GlassField(icon: "key.fill", placeholder: "API token (TTV_API_TOKEN)", text: $token, secure: true)
                        GlassField(icon: "timer", placeholder: "Auto-refresh seconds", text: $refresh, keyboard: .numberPad)
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        CardHeader(title: "Connection", icon: "bolt.horizontal")
                        HStack {
                            GlassButton(title: "Test", icon: "dot.radiowaves.left.and.right", tint: Theme.twitch) {
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

                GlassButton(title: "Save", icon: "checkmark", tint: Theme.twitch, prominent: true) {
                    apply()
                }
                .frame(maxWidth: .infinity)

                SecondaryLabel(
                    "The token is TTV_API_TOKEN from the miner's .env. It never leaves this phone.",
                    font: .caption2
                )
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(AppBackground())
        .navigationTitle("Settings")
        .onAppear { fill() }
    }

    private func fill() {
        host = settings.host
        port = String(settings.port)
        token = settings.token
        refresh = String(settings.refreshSeconds)
    }

    private func current() -> MinerSettings {
        let h = host.trimmingCharacters(in: .whitespaces)
        return MinerSettings(
            host: h.isEmpty ? settings.host : h,
            port: Int(port) ?? settings.port,
            token: token,
            refreshSeconds: Int(refresh) ?? settings.refreshSeconds
        )
    }

    private func test() async {
        testing = true
        defer { testing = false }
        let api = MinerAPI(settings: current())
        do {
            let running = try await api.minerStatus()
            testResult = running ? "Connected — miner is running" : "Connected — miner process offline"
            testOk = true
        } catch {
            testResult = error.messageText
            testOk = false
        }
    }

    private func apply() {
        let s = current()
        s.save()
        onApplied(s)
    }
}
