import SwiftUI
import UIKit

/// The cardless card content for one pulse — author row, tier-scaled body (or
/// emoji hero), the UFI strip (reactions + reply), and the inline reply preview.
/// Ported from PulseHubFeedCard (+Body, +UFI). Media/url/youtube bodies render
/// their caption text for now (those blocks are the next port).
struct PulseCardView: View {
    let pulse: PulseEntity
    let author: PulseAuthor?
    let isOwn: Bool
    let currentUserID: UUID
    var forceExpanded: Bool = false
    let onReact: (String) -> Void
    let onReply: () -> Void
    var onAction: (PulseCardAction) -> Void = { _ in }

    @AppStorage("pulseCardStyle") private var cardStyle: PulseCardStyle = .sansSerif
    @State private var expanded = false
    @State private var showPicker = false
    @State private var showReactors = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            authorRow
            bodyContent
            ufiRow
            if !pulse.isEphemeral && pulse.replyCount > 0 {
                PulseReplyPreview(pulse: pulse, onTap: onReply).padding(.top, 2)
            }
        }
        .padding(.trailing, 12)
        .contextMenu { overflowMenu } preview: { menuPreview }
        .sheet(isPresented: $showReactors) {
            PulseReactorsSheet(reactions: pulse.reactions)
                .presentationDetents([.medium])
        }
    }

    /// The pop-out preview for the long-press menu. The live card's background is
    /// the glass pane on the parent row, which a contextMenu snapshot of this
    /// content can't capture — so the preview supplies its own opaque card
    /// background, otherwise it floats transparently over the dimmed feed.
    private var menuPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            authorRow
            bodyContent
        }
        .padding(12)
        .frame(maxWidth: 360, alignment: .leading)
        .background(Color(.systemBackground))
    }

    // Long-press management menu — React submenu + owner actions.
    @ViewBuilder
    private var overflowMenu: some View {
        Menu("React") {
            ForEach(pulseQuickReactions, id: \.self) { e in
                Button(e) { onReact(e) }
            }
        }
        Button { onAction(.copy) } label: { Label("Copy", systemImage: "doc.on.doc") }
        if isOwn {
            Button { onAction(.edit) } label: { Label("Edit", systemImage: "pencil") }
            Menu {
                Button("1 hour") { onAction(.setExpiry(3600)) }
                Button("1 day") { onAction(.setExpiry(86400)) }
                Button("Make permanent") { onAction(.setExpiry(nil)) }
            } label: { Label("Set expiry", systemImage: "timer") }
            Button(role: .destructive) { onAction(.delete) } label: { Label("Delete", systemImage: "trash") }
        }
    }

    // MARK: - Author row

    private var authorRow: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                Text(author?.displayName ?? "…")
                    .font(.system(size: 16, weight: .semibold)).lineLimit(1)
                if pulse.isEdited {
                    Text("· edited").font(.system(size: 11, weight: .medium)).italic()
                        .foregroundStyle(.secondary)
                }
                if let glyph = pulse.kindGlyph {
                    Image(systemName: glyph).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                }
                if pulse.isPrivate {
                    Image(systemName: "person.2.fill").font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.accentColor).accessibilityLabel("Private pulse")
                }
                Spacer(minLength: 0)
            }
            Text(pulse.stamp).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }

    // MARK: - Body

    @ViewBuilder
    private var bodyContent: some View {
        switch pulse.textShape {
        case .emojiOnly:
            Text(pulse.emojiOnlyGlyph)
                .font(.system(size: 64))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 10)
        case .text:
            // Twitter convention: text IS the post; media/link is the attachment.
            VStack(alignment: .leading, spacing: 8) {
                if !pulse.text.isEmpty { textBody }
                if pulse.youtubeMatch != nil {
                    // YouTube takes priority over kind=url so a url-kind YouTube
                    // link gets the dedicated video card.
                    PulseYouTubeBlock(pulse: pulse)
                } else {
                    switch pulse.kind {
                    case "image", "gallery", "video", "audio", "file":
                        PulseMediaBlock(pulse: pulse)
                    case "url":
                        PulseLinkBlock(pulse: pulse)
                    default:
                        if pulse.hasMedia { PulseMediaBlock(pulse: pulse) }
                    }
                }
            }
        case .empty:
            EmptyView()
        }
    }

    @ViewBuilder
    private var textBody: some View {
        let tier = pulse.textTier
        VStack(alignment: .leading, spacing: 4) {
            Text(pulse.text)
                .font(tier.font(style: cardStyle))
                .lineSpacing(tier.lineSpacing)
                .multilineTextAlignment(.leading)
                .lineLimit(tier.collapses && !expanded && !forceExpanded ? 10 : nil)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if tier.collapses && !forceExpanded {
                Button(expanded ? "Show less" : "Show more") { withAnimation { expanded.toggle() } }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .buttonStyle(.plain)
            }
        }
    }

    // MARK: - UFI (reactions + reply)

    private var ufiRow: some View {
        let mine = pulse.userReaction(userID: currentUserID)
        return HStack(spacing: 8) {
            ForEach(pulse.reactionSummary, id: \.emoji) { r in
                // Tap a chip → who-reacted sheet (the host app's reactors sheet).
                PulseReactionChip(emoji: r.emoji, count: r.count, isMine: mine == r.emoji) { showReactors = true }
            }
            Button { showPicker = true } label: {
                Image(systemName: "face.smiling").font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary).frame(width: 36, height: 36).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showPicker) {
                PulseReactionPicker(current: mine) { onReact($0); showPicker = false }
            }
            Spacer()
            // Reply is gated to kept pulses — ephemeral pulses are flickering
            // thoughts and the design locks replies to kept pulses only.
            if !pulse.isEphemeral {
                Button(action: onReply) {
                    HStack(spacing: 6) {
                        Image(systemName: "bubble.left").font(.system(size: 16, weight: .medium))
                        Text(replyLabel).font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.secondary).frame(minHeight: 36).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 2)
    }

    private var replyLabel: String {
        switch pulse.replyCount {
        case 0:  return "Leave a reply"
        case 1:  return "1 reply"
        default: return "\(pulse.replyCount) replies"
        }
    }
}

/// One reaction pill (own reaction tinted to accent). Extracted to keep the UFI
/// row cheap to type-check.
struct PulseReactionChip: View {
    let emoji: String
    let count: Int
    let isMine: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(emoji).font(.system(size: 18))
                Text("\(count)").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isMine ? Color.accentColor : Color.secondary)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 4).frame(minHeight: 36).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
