import SwiftUI

/// Inline reply-preview row — a face + "Name: snippet" + count, tap routes to
/// the (future) detail view. Ported/simplified from PulseReplyPreviewRow; the
/// multi-avatar facepile is a follow-up once replies carry richer author data.
struct PulseReplyPreview: View {
    let pulse: PulseEntity
    let onTap: () -> Void

    @Environment(\.colorScheme) private var cs
    @State private var author: PulseAuthor?

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 8) {
                PulseAvatar(author: author, size: 22)
                    .overlay(Circle().strokeBorder(faceRing, lineWidth: 1.5))
                snippet
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary.opacity(0.5))
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.secondary.opacity(0.08)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .task(id: pulse.replyPreviewUserId) {
            if let uid = pulse.replyPreviewUserId { author = await PulseAuthorBox.resolve(uid) }
        }
    }

    private var faceRing: Color { cs == .dark ? Color(white: 0.12) : Color(white: 0.97) }

    private var snippet: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text(author?.displayName ?? "Someone")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.primary)
                Text(snippetText)
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.tail)
            }
            if pulse.replyCount > 1 {
                Text("\(pulse.replyCount) replies")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary.opacity(0.7))
            }
        }
    }

    private var snippetText: String {
        let t = (pulse.replyPreviewText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return ": \(t)" }
        if let e = pulse.replyPreviewEmoji, !e.isEmpty { return ": \(e)" }
        return " replied"
    }
}

/// A tiny main-actor holder so subviews can reach the host's author resolver
/// without threading it through every initializer. Set once by PulseFeedView.
@MainActor
enum PulseAuthorBox {
    private static var resolver: (any PulseAuthorResolving)?
    static func configure(_ r: any PulseAuthorResolving) { resolver = r }
    static func resolve(_ id: UUID) async -> PulseAuthor? {
        await resolver?.author(for: id)
    }
}
