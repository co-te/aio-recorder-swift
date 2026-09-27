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
    static let cyan = Color(red: 0x06/255, green: 0xB6/255, blue: 0xD4/255)
    static let tangoOrange = Color(red: 0xF9/255, green: 0x73/255, blue: 0x16/255)
    static let telegramSky = Color(red: 0x38/255, green: 0xBD/255, blue: 0xF8/255)
    static let tiktokPink = Color(red: 0xFE/255, green: 0x2C/255, blue: 0x55/255)
    static let stripPink = Color(red: 0xFF/255, green: 0x7A/255, blue: 0xB8/255)

    static let bgTop = Color(red: 0x14/255, green: 0x0C/255, blue: 0x26/255)   // purple-leaning
    static let bgBottom = Color(red: 0x0A/255, green: 0x07/255, blue: 0x14/255)

    static let cardFallback = Color.white.opacity(0.06)
    static let textPrimary = Color.white.opacity(0.94)
    static let textSecondary = Color.white.opacity(0.58)

    static let surfaceBg = Color.white.opacity(0.05)
    static let surfaceBorder = Color.white.opacity(0.12)

    static var isGlass: Bool { false }

    static func apply() {
        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav

        let tab = UITabBarAppearance()
        tab.configureWithTransparentBackground()
        tab.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        UITabBar.appearance().standardAppearance = tab
        if #available(iOS 15.0, *) {
            UITabBar.appearance().scrollEdgeAppearance = tab
        }
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
    var padding: CGFloat = 16
    let content: Content

    init(padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(Theme.cardFallback)
            .background(.ultraThinMaterial)
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
    var isFullWidth = false
    let action: () -> Void

    init(
        title: String,
        icon: String? = nil,
        tint: Color = Theme.blue,
        prominent: Bool = false,
        isFullWidth: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.tint = tint
        self.prominent = prominent
        self.isFullWidth = isFullWidth
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon) }
                Text(title).font(.subheadline).fontWeight(.semibold)
            }
            .frame(maxWidth: isFullWidth ? .infinity : nil)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .buttonStyle(BouncyButtonStyle())
        .foregroundStyle(prominent ? .white : tint)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(prominent ? AnyShapeStyle(tint) : AnyShapeStyle(Color.white.opacity(0.08)))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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

// MARK: - Modern UI Components

struct BouncyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.88 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct PulsingRadar: View {
    let color: Color
    var size: CGFloat = 8
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.55), lineWidth: 2)
                .scaleEffect(pulse ? 2.4 : 1.0)
                .opacity(pulse ? 0 : 0.8)
            Circle()
                .fill(color)
                .frame(width: size, height: size)
        }
        .frame(width: size * 2.4, height: size * 2.4)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
    }
}

struct BentoCard<Content: View>: View {
    var headerIcon: String? = nil
    var headerTitle: String? = nil
    var headerSubtitle: String? = nil
    var headerBadge: String? = nil
    var badgeColor: Color = Theme.blue
    let content: Content

    init(
        headerIcon: String? = nil,
        headerTitle: String? = nil,
        headerSubtitle: String? = nil,
        headerBadge: String? = nil,
        badgeColor: Color = Theme.blue,
        @ViewBuilder content: () -> Content
    ) {
        self.headerIcon = headerIcon
        self.headerTitle = headerTitle
        self.headerSubtitle = headerSubtitle
        self.headerBadge = headerBadge
        self.badgeColor = badgeColor
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if headerTitle != nil || headerIcon != nil || headerBadge != nil {
                HStack(spacing: 8) {
                    if let headerIcon {
                        Image(systemName: headerIcon)
                            .font(.subheadline)
                            .foregroundStyle(badgeColor)
                    }
                    if let headerTitle {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(headerTitle)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(Theme.textPrimary)
                            if let headerSubtitle {
                                Text(headerSubtitle)
                                    .font(.caption2)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                    Spacer()
                    if let headerBadge {
                        Text(headerBadge)
                            .font(.caption2)
                            .fontWeight(.bold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(badgeColor.opacity(0.18), in: Capsule())
                            .foregroundStyle(badgeColor)
                    }
                }
            }
            content
        }
        .padding(16)
        .background(Theme.cardFallback)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
        )
    }
}

struct MetricCard: View {
    let icon: String
    let title: String
    let value: String
    var subtitle: String? = nil
    var tint: Color = Theme.blue
    var action: (() -> Void)? = nil

    var body: some View {
        Button {
            action?()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(tint)
                        .frame(width: 32, height: 32)
                        .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Spacer()
                    if action != nil {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(Theme.textSecondary.opacity(0.6))
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(value)
                        .font(.system(.title2, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(title)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(tint)
                            .lineLimit(1)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cardFallback)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
            )
        }
        .buttonStyle(BouncyButtonStyle())
        .disabled(action == nil)
    }
}

struct CapsuleFilterChip: View {
    let title: String
    var icon: String? = nil
    var badge: String? = nil
    var badgeColor: Color = Theme.blue
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.caption)
                }
                Text(title)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .medium)
                if let badge {
                    Text(badge)
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(badgeColor.opacity(isSelected ? 0.35 : 0.20), in: Capsule())
                        .foregroundStyle(isSelected ? .white : badgeColor)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
            .background(
                Capsule()
                    .fill(isSelected ? Color.white.opacity(0.16) : Color.white.opacity(0.05))
            )
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? Color.white.opacity(0.3) : Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(BouncyButtonStyle())
    }
}

extension Error {
    var messageText: String {
        if let e = self as? APIError { return e.message.isEmpty ? "HTTP \(e.statusCode)" : e.message }
        return localizedDescription
    }
}
