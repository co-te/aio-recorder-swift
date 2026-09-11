//
//  Theme.swift — shared glass design system (same as LiveRecorder).
//

import SwiftUI
import UIKit

enum Theme {
    static let blue = Color(red: 0x3B/255, green: 0x82/255, blue: 0xF6/255)
    static let green = Color(red: 0x22/255, green: 0xC5/255, blue: 0x5E/255)
    static let red = Color(red: 0xEF/255, green: 0x44/255, blue: 0x44/255)
    static let warn = Color(red: 0xFF/255, green: 0xB0/255, blue: 0x20/255)
    static let twitch = Color(red: 0x91/255, green: 0x46/255, blue: 0xFF/255)
    static let gold = Color(red: 0xFF/255, green: 0xC1/255, blue: 0x07/255)

    static let bgTop = Color(red: 0x14/255, green: 0x0C/255, blue: 0x26/255)   // purple-leaning
    static let bgBottom = Color(red: 0x0A/255, green: 0x07/255, blue: 0x14/255)

    static let cardFallback = Color.white.opacity(0.06)
    static let textPrimary = Color.white.opacity(0.94)
    static let textSecondary = Color.white.opacity(0.58)

    static var isGlass: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }

    static func apply() {
        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
    }
}

struct AppBackground: View {
    var body: some View {
        LinearGradient(
            colors: [Theme.bgTop, Theme.bgBottom],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
        .overlay(
            RadialGradient(
                colors: [Theme.twitch.opacity(0.16), .clear],
                center: .topLeading,
                startRadius: 10, endRadius: 520
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        )
    }
}

struct GlassCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                content
                    .glassEffect(.regular, in: .rect(cornerRadius: 20, style: .continuous))
            } else {
                content
                    .background(Theme.cardFallback)
                    .background(.ultraThinMaterial)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
        )
    }
}

struct GlassButton: View {
    let title: String
    var icon: String? = nil
    var tint: Color = Theme.blue
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon) }
                Text(title).font(.subheadline).fontWeight(.semibold)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .foregroundStyle(prominent ? .white : tint)
        .background(
            Group {
                if #available(iOS 26.0, *) {
                    GlassEffectContainer {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(prominent ? AnyShapeStyle(tint) : AnyShapeStyle(.clear))
                            .glassEffect(
                                prominent ? .regular.tint(tint.opacity(0.35)) : .regular,
                                in: .rect(cornerRadius: 14, style: .continuous)
                            )
                    }
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(prominent ? AnyShapeStyle(tint) : AnyShapeStyle(Color.white.opacity(0.08)))
                }
            }
        )
    }
}

struct CardHeader: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(Theme.twitch)
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.textPrimary)
            Spacer()
        }
    }
}

struct SecondaryLabel: View {
    let text: String
    var font: Font = .caption
    init(_ text: String, font: Font = .caption) {
        self.text = text
        self.font = font
    }
    var body: some View {
        Text(text).font(font).foregroundStyle(Theme.textSecondary)
    }
}

struct ErrorStateView: View {
    let message: String
    var retryAction: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Theme.red.opacity(0.15))
                    .frame(width: 72, height: 72)
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 30))
                    .foregroundStyle(Theme.red)
            }
            Text("Failed to reach the miner")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Text(message)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            GlassButton(title: "Retry", icon: "arrow.clockwise", tint: Theme.twitch, prominent: true) {
                retryAction()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

extension Error {
    var messageText: String {
        if let e = self as? APIError { return e.message.isEmpty ? "HTTP \(e.statusCode)" : e.message }
        return localizedDescription
    }
}
