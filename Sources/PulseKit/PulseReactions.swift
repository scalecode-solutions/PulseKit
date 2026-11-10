import SwiftUI

/// Default quick-reactions row (iMessage-tapback shape).
let pulseQuickReactions = ["👍", "❤️", "😂", "😮", "😢", "🔥"]

/// Horizontal reaction picker — shown from the smiley button / long-press. The
/// caller's current reaction is highlighted; tapping commits (or toggles off).
struct PulseReactionPicker: View {
    let current: String?
    let onPick: (String) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(pulseQuickReactions, id: \.self) { emoji in
                Button { onPick(emoji) } label: {
                    Text(emoji)
                        .font(.system(size: 30))
                        .padding(8)
                        .background(
                            Circle().fill(current == emoji ? Color.accentColor.opacity(0.2) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .presentationCompactAdaptation(.popover)
    }
}

/// Who-reacted sheet — grouped by emoji, names resolved via the host roster.
struct PulseReactorsSheet: View {
    let reactions: [String: [UUID]]
    @State private var names: [UUID: String] = [:]
    @Environment(\.dismiss) private var dismiss

    private var rows: [(emoji: String, users: [UUID])] {
        reactions.map { ($0.key, $0.value) }.filter { !$0.users.isEmpty }.sorted { $0.users.count > $1.users.count }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(rows, id: \.emoji) { row in
                    Section {
                        ForEach(row.users, id: \.self) { uid in
                            HStack(spacing: 10) {
                                Text(row.emoji).font(.title3)
                                Text(names[uid] ?? "…")
                                Spacer()
                            }
                        }
                    }
                }
            }
            .pulseInlineNavTitle("Reactions")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .task {
            for uid in reactions.values.flatMap({ $0 }) where names[uid] == nil {
                names[uid] = (await PulseAuthorBox.resolve(uid))?.displayName ?? "Someone"
            }
        }
    }
}

/// Overflow / management actions raised from the card's long-press menu.
enum PulseCardAction: Sendable {
    case copy
    case edit
    case delete
    case setExpiry(Int?) // seconds; nil = make permanent
}
