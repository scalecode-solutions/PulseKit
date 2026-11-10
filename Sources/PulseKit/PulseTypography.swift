import SwiftUI

// Ported from the host app's PulseTypography — the text-tier type scale and shape
// classification. Pure value logic, no host dependencies.

/// User-selectable font design for text pulses (overflow menu, persisted).
public enum PulseCardStyle: String, CaseIterable, Identifiable, Sendable {
    case sansSerif = "default" // SF Pro — casual, Post-It
    case serif                 // New York — journal
    case rounded               // SF Rounded — warm

    public var id: String { rawValue }

    public var swiftUIDesign: Font.Design {
        switch self {
        case .sansSerif: return .default
        case .serif:     return .serif
        case .rounded:   return .rounded
        }
    }

    public var displayName: String {
        switch self {
        case .sansSerif: return "Default"
        case .serif:     return "Serif"
        case .rounded:   return "Rounded"
        }
    }
}

/// Content shape of a pulse — drives whether the card renders a big emoji hero
/// or tier-scaled text.
public enum PulseTextShape: Sendable {
    case empty
    case emojiOnly
    case text
}

/// Length-driven type scale for text pulses (0–2000 chars → 20…12pt).
public enum PulseTextTier: Sendable {
    case short      // 0–100
    case medium     // 101–500
    case long       // 501–1000
    case extended   // 1001–1500
    case essay      // 1501–2000

    public func font(style: PulseCardStyle) -> Font {
        switch self {
        case .short:    return .system(size: 20, weight: .medium,  design: style.swiftUIDesign)
        case .medium:   return .system(size: 18, weight: .regular, design: style.swiftUIDesign)
        case .long:     return .system(size: 16, weight: .regular, design: style.swiftUIDesign)
        case .extended: return .system(size: 14, weight: .regular, design: style.swiftUIDesign)
        case .essay:    return .system(size: 12, weight: .regular, design: style.swiftUIDesign)
        }
    }

    public var lineSpacing: CGFloat {
        switch self {
        case .short:    return 4
        case .medium:   return 3
        case .long:     return 2
        case .extended, .essay: return 1
        }
    }

    /// Long bodies collapse to a few lines with a "Show more" affordance.
    public var collapses: Bool {
        switch self {
        case .short, .medium: return false
        case .long, .extended, .essay: return true
        }
    }

    /// Emoji-watermark size for this tier (90→80→70, then plateaus).
    public var watermarkSize: CGFloat {
        switch self {
        case .short:    return 90
        case .medium:   return 80
        case .long, .extended, .essay: return 70
        }
    }
}

extension String {
    /// True if, after stripping whitespace, every scalar is emoji — detects
    /// pulses like "🔥🔥🔥" that should render emoji-only. (The host app's exact rule.)
    var isOnlyEmoji: Bool {
        let stripped = filter { !$0.isWhitespace }
        guard !stripped.isEmpty else { return false }
        return stripped.unicodeScalars.allSatisfy { $0.properties.isEmoji }
    }
}
