import Foundation

// Display-layer computed properties on the persisted entity, ported from
// The host app's `Pulse` model. Pure reads; called from the (main-actor) card view.

public extension PulseEntity {
    var isEdited: Bool { editedAt != nil }
    var isPrivate: Bool { (audience?.isEmpty == false) }
    var isEphemeral: Bool { expiresAt != nil }

    /// Decoded media attachments.
    var files: [MediaRef] {
        guard let filesData, let f = try? JSONDecoder().decode([MediaRef].self, from: filesData) else { return [] }
        return f
    }
    /// Decoded link preview.
    var linkPreview: LinkPreview? {
        guard let linkPreviewData else { return nil }
        return try? JSONDecoder().decode(LinkPreview.self, from: linkPreviewData)
    }
    var hasMedia: Bool { !files.isEmpty || (mediaUrl?.isEmpty == false) }

    var textShape: PulseTextShape {
        if hasMedia { return .text }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let hasEmoji = emoji?.isEmpty == false
        if trimmed.isEmpty { return hasEmoji ? .emojiOnly : .empty }
        if trimmed.isOnlyEmoji { return .emojiOnly }
        return .text
    }

    var textTier: PulseTextTier {
        switch text.count {
        case 0...100:     return .short
        case 101...500:   return .medium
        case 501...1000:  return .long
        case 1001...1500: return .extended
        default:          return .essay
        }
    }

    /// The single glyph to render as the hero when `textShape == .emojiOnly`.
    var emojiOnlyGlyph: String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isOnlyEmoji { return trimmed }
        return emoji ?? ""
    }

    /// Inline kind hint for non-self-evident kinds (SF Symbol name).
    var kindGlyph: String? {
        switch kind {
        case "audio": return "waveform"
        case "poll":  return "chart.bar"
        case "file":  return "doc"
        default:      return nil
        }
    }

    /// Reactions as (emoji, count), highest first.
    var reactionSummary: [(emoji: String, count: Int)] {
        reactions
            .map { (emoji: $0.key, count: $0.value.count) }
            .filter { $0.count > 0 }
            .sorted { $0.count > $1.count }
    }

    /// The emoji this user reacted with, if any.
    func userReaction(userID: UUID) -> String? {
        for (emoji, ids) in reactions where ids.contains(userID) { return emoji }
        return nil
    }

    /// Compact remaining-TTL label for ephemeral pulses ("<1m", "37m", "4h", "2d").
    var expiryCountdown: String? {
        guard let expiresAt else { return nil }
        let now = Date().timeIntervalSince1970 * 1000
        let remaining = Double(expiresAt) - now
        guard remaining > 0 else { return nil }
        let minutes = remaining / 1000 / 60
        let hours = minutes / 60
        if minutes < 1 { return "<1m" }
        if minutes < 60 { return "\(Int(minutes))m" }
        if hours < 24 { return "\(Int(hours))h" }
        return "\(Int(hours / 24))d"
    }

    /// Self-contained calendar stamp ("Today, 3:42 PM" / "Apr 15, 3:42 PM").
    var stamp: String {
        let date = Date(timeIntervalSince1970: Double(createdAt) / 1000)
        let cal = Calendar.current
        let now = Date()
        let t = DateFormatter()
        t.dateFormat = "h:mm a"
        let time = t.string(from: date)
        if cal.isDateInToday(date) { return "Today, \(time)" }
        if cal.isDateInYesterday(date) { return "Yesterday, \(time)" }
        let days = cal.dateComponents([.day], from: date, to: now).day ?? 0
        let f = DateFormatter()
        if days < 7 {
            f.dateFormat = "EEEE"
        } else {
            f.dateFormat = cal.isDate(date, equalTo: now, toGranularity: .year) ? "MMM d" : "MMM d, yyyy"
        }
        return "\(f.string(from: date)), \(time)"
    }
}
