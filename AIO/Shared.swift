//
//  Shared.swift — single APIError, formatting, glass field, shared views.
//

import SwiftUI

// MARK: - Shared error (used by all four backend clients)

struct APIError: Error, LocalizedError {
    let statusCode: Int
    let message: String
    var errorDescription: String? { message.isEmpty ? "HTTP \(statusCode)" : message }
}

// MARK: - Format

enum Fmt {
    static func points(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 10_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }

    static func bytes(_ n: Int) -> String {
        guard n > 0 else { return "0 B" }
        let units = ["B", "KB", "MB", "GB", "TB"]
        var v = Double(n)
        var i = 0
        while v >= 1024 && i < units.count - 1 { v /= 1024; i += 1 }
        return String(format: i >= 2 ? "%.1f %@" : "%.0f %@", v, units[i])
    }

    static func duration(_ seconds: Double) -> String {
        let s = Int(seconds)
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m \(s % 60)s" }
        return "\(s / 3600)h \((s % 3600) / 60)m"
    }

    static func date(_ unix: Int) -> String {
        guard unix > 0 else { return "" }
        let dt = Date(timeIntervalSince1970: TimeInterval(unix))
        if Calendar.current.isDateInToday(dt) {
            return "Today " + dt.formatted(date: .omitted, time: .shortened)
        }
        return dt.formatted(date: .numeric, time: .omitted)
    }

    static func iso(_ s: String?) -> String {
        guard let s, !s.isEmpty else { return "" }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) {
            return d.formatted(date: .numeric, time: .shortened)
        }
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        if let d = f2.date(from: s) {
            return d.formatted(date: .numeric, time: .shortened)
        }
        return s
    }

    static func logTime(_ t: Double) -> String {
        Date(timeIntervalSince1970: t).formatted(date: .omitted, time: .shortened)
    }
}

// MARK: - Glass field (fill only — parent GlassCard draws the single border)

struct GlassField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var secure = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(Theme.textSecondary)
            Group {
                if secure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .keyboardType(keyboard)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .foregroundStyle(Theme.textPrimary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }
}

// MARK: - Authed thumbnail (AsyncImage can't send Bearer headers)

struct AuthedImage: View {
    let api: DriveAPI
    let file: TDFile
    var size: CGFloat = 44

    @State private var data: Data?

    var body: some View {
        Group {
            if let data, let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Self.iconColor(for: file.type).opacity(0.12))
                    .overlay {
                        Image(systemName: Self.icon(for: file.type))
                            .foregroundStyle(Self.iconColor(for: file.type))
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .task {
            guard file.hasThumb, data == nil else { return }
            data = try? await api.thumbData(file)
        }
    }

    static func icon(for type: String) -> String {
        switch type {
        case "image": return "photo"
        case "video": return "film"
        case "audio": return "waveform"
        case "text", "message": return "doc.text"
        case "link": return "link"
        default: return "doc"
        }
    }

    static func iconColor(for type: String) -> Color {
        switch type {
        case "video": return Theme.telegramSky
        case "image": return Theme.tiktokPink
        case "audio": return Theme.warn
        case "text", "message": return Theme.green
        case "link": return Theme.cyan
        default: return Theme.textSecondary
        }
    }
}

// MARK: - File row

struct FileRow: View {
    let api: DriveAPI
    let file: TDFile

    var body: some View {
        HStack(spacing: 12) {
            AuthedImage(api: api, file: file)
            VStack(alignment: .leading, spacing: 3) {
                Text(file.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(Fmt.bytes(file.size))
                    if !Fmt.date(file.date).isEmpty { Text("· \(Fmt.date(file.date))") }
                    if let g = file.group, !g.isEmpty { Text("· \(g)") }
                }
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if file.favorite {
                Image(systemName: "star.fill").font(.caption).foregroundStyle(Theme.gold)
            }
            if file.pinned {
                Image(systemName: "pin.fill").font(.caption).foregroundStyle(Theme.textSecondary)
            }
            if file.offline {
                Image(systemName: "arrow.down.circle.fill").font(.caption).foregroundStyle(Theme.green)
            }
        }
        .padding(12)
    }
}

// MARK: - Status pill

struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.18))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}
