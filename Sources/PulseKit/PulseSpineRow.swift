import SwiftUI

/// One pulse row: spine column (avatar anchor → grey line → kind/expiry node
/// dot) + the cardless card content, in a clear glass pane, with the author's
/// emoji watermark bleeding off the top-right corner and an accent stroke on
/// your own pulses. Ported from PulseHubFeedRow.
struct PulseSpineRow: View {
    let pulse: PulseEntity
    let author: PulseAuthor?
    let currentUserID: UUID
    var forceExpanded: Bool = false
    let onReact: (String) -> Void
    let onReply: () -> Void
    var onAction: (PulseCardAction) -> Void = { _ in }

    @Environment(\.colorScheme) private var cs

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            spineColumn
            PulseCardView(pulse: pulse, author: author, isOwn: isOwn,
                          currentUserID: currentUserID, forceExpanded: forceExpanded,
                          onReact: onReact, onReply: onReply, onAction: onAction)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topTrailing) { watermark }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .pulseGlassPane(14)
        .overlay(cardStroke)
    }

    // MARK: - Spine

    private var spineColumn: some View {
        VStack(spacing: 0) {
            PulseAvatar(author: author, size: 40)
            Rectangle()
                .fill(cs == .dark ? Color(white: 0.22) : Color(white: 0.82))
                .frame(width: 1.5)
                .frame(maxHeight: .infinity)
            PulseNodeDot(pulse: pulse)
        }
        .frame(width: 40)
    }

    // MARK: - Watermark (author emoji → single-emoji text → 💌)

    private var watermarkContent: String {
        if let e = pulse.emoji, !e.isEmpty { return e }
        let trimmed = pulse.text.trimmingCharacters(in: .whitespaces)
        if trimmed.isOnlyEmoji, trimmed.count == 1 { return trimmed }
        return "💌"
    }

    private var watermark: some View {
        Text(watermarkContent)
            .font(.system(size: pulse.textTier.watermarkSize))
            .opacity(cs == .dark ? 0.22 : 0.15)
            .mask(
                LinearGradient(
                    stops: [.init(color: .white, location: 0),
                            .init(color: .white, location: 0.45),
                            .init(color: .clear, location: 1)],
                    startPoint: .bottomLeading, endPoint: .topTrailing)
            )
            .offset(x: 12, y: -12)
            .allowsHitTesting(false)
    }

    /// Every card gets a hairline so it reads against a white feed in light mode
    /// (the clear glass pane alone is near-invisible there). Your own pulses get
    /// the accent tint instead of the neutral line, as the "this one's mine" cue.
    private var cardStroke: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(
                isOwn ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.08),
                lineWidth: 1
            )
    }

    private var isOwn: Bool { pulse.userId == currentUserID }
}
