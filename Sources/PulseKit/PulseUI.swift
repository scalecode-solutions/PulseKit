import SwiftUI
import UIKit

// Shared UI primitives for the pulse card — the glass pane, the avatar, and the
// spine terminator node dot. Ported from the host app, adapted to PulseKit's models
// and themeable colors (host's tint = the old AppColors.primary; semantic
// .primary/.secondary for text; inline greys for the spine).

extension View {
    /// Inline nav title.
    func pulseInlineNavTitle(_ title: String) -> some View {
        self.navigationTitle(title).navigationBarTitleDisplayMode(.inline)
    }

    /// The cardless glass pane (iOS 26 Liquid Glass; material fallback for the
    /// macOS test build / older OSes).
    @ViewBuilder
    func pulseGlassPane(_ cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26, macOS 26, *) {
            self.glassEffect(.clear, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }
}

/// Avatar — renders the base64 thumbnail carried in `PulseAuthor.avatarRef`
/// (synced through the social graph's people directory), with an initials-circle
/// fallback when there's no photo. Decoded once per person and cached.
struct PulseAvatar: View {
    let author: PulseAuthor?
    var size: CGFloat = 40

    var body: some View {
        // Host-provided avatar (e.g. The host app's ProfileImageView) takes over fully —
        // it owns its own size + shape. Otherwise the built-in base64/initials.
        if let hostView = PulseAvatarBox.view(for: author, size: size) {
            hostView
        } else {
            BuiltInAvatar(author: author, size: size)
        }
    }
}

private struct BuiltInAvatar: View {
    let author: PulseAuthor?
    let size: CGFloat
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Circle()
                    .fill(Color.accentColor.opacity(0.18))
                    .overlay(
                        Text(initials)
                            .font(.system(size: size * 0.4, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    )
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: author?.userID) { image = PulseAvatarCache.image(for: author) }
    }

    private var initials: String {
        guard let name = author?.displayName, !name.isEmpty else { return "?" }
        return name.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased()
    }
}

/// Optional host-provided avatar rendering. When the host injects a view-builder
/// (the host app passes its `ProfileImageView`), PulseKit renders it wherever avatars
/// go and `PulseAuthor.avatarRef` becomes host-interpreted (a photoRef, a URL,
/// whatever the host's view understands). Configured by `PulseFeedView`; a static
/// box (like `PulseAuthorBox`) because `navigationDestination` hoists views above
/// the environment.
@MainActor
enum PulseAvatarBox {
    private static var builder: ((PulseAuthor, CGFloat) -> AnyView)?
    static func configure(_ b: ((PulseAuthor, CGFloat) -> AnyView)?) { builder = b }
    static func view(for author: PulseAuthor?, size: CGFloat) -> AnyView? {
        guard let builder, let author else { return nil }
        return builder(author, size)
    }
}

/// Decodes + caches avatar thumbnails so a base64 blob is turned into a UIImage
/// once per person, not on every render or scroll-reuse.
enum PulseAvatarCache {
    // NSCache is documented thread-safe; the unchecked annotation reflects that.
    nonisolated(unsafe) private static let cache = NSCache<NSString, UIImage>()

    static func image(for author: PulseAuthor?) -> UIImage? {
        guard let author, let b64 = author.avatarRef, !b64.isEmpty else { return nil }
        let key = author.userID.uuidString as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let data = Data(base64Encoded: b64), let img = UIImage(data: data) else { return nil }
        cache.setObject(img, forKey: key)
        return img
    }
}

/// Spine terminator node — kind color + live expiry arc + stays-ring + grow/red
/// when expiring soon. Ported from PulseHubFeedDot. (Read-state styling is a
/// future layer here; today it encodes kind + expiry, exactly as the host app ships.)
struct PulseNodeDot: View {
    let pulse: PulseEntity
    @Environment(\.colorScheme) private var cs

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date
            let expiring = isExpiringSoon(now: now)
            let size: CGFloat = expiring ? 10 : 8
            let base = expiring ? Color.red : kindColor

            ZStack {
                if let progress = lifeProgress(now: now) {
                    Circle()
                        .trim(from: progress, to: 1)
                        .stroke(base.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 18, height: 18)
                }
                if pulse.expiresAt == nil {
                    Circle().stroke(base.opacity(0.35), lineWidth: 1).frame(width: 15, height: 15)
                }
                Circle().fill(base).frame(width: size, height: size)
                if let glyph = pulse.kindGlyph {
                    Image(systemName: glyph).font(.system(size: 5, weight: .bold)).foregroundStyle(.background)
                }
            }
            .frame(width: 24, height: 24)
            .animation(.easeInOut(duration: 0.3), value: expiring)
        }
    }

    private var kindColor: Color {
        switch pulse.kind {
        case "image", "gallery": return Color.accentColor
        case "video":            return .purple
        case "audio":            return .teal
        case "url":              return .blue
        case "poll":             return .orange
        case "file":             return .brown
        default:                 return pulse.textShape == .emojiOnly ? .pink : neutralDot
        }
    }

    private var neutralDot: Color { cs == .dark ? Color(white: 0.4) : Color(white: 0.65) }

    private func lifeProgress(now: Date) -> Double? {
        guard let expiresAtMs = pulse.expiresAt else { return nil }
        let created = Double(pulse.createdAt) / 1000
        let total = Double(expiresAtMs) / 1000 - created
        guard total > 0 else { return 1 }
        return max(0, min(1, (now.timeIntervalSince1970 - created) / total))
    }

    private func isExpiringSoon(now: Date) -> Bool {
        guard let expiresAtMs = pulse.expiresAt else { return false }
        let remaining = Double(expiresAtMs) / 1000 - now.timeIntervalSince1970
        return remaining > 0 && remaining < 10 * 60
    }
}
