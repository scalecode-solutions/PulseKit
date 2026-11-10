import SwiftUI
import SwiftData

/// The pulse detail — the pinned parent (uncollapsed) + its replies, with a
/// pinned bottom reply bar. Replies are deliberately light: a touch, not a
/// thread. Real conversation lives in chat. Ported from the host app's PulseDetailView.
struct PulseDetailView: View {
    let config: PulseConfig
    let sync: PulseSync

    @Query private var parents: [PulseEntity]
    @Query private var replies: [ReplyEntity]
    @State private var parentAuthor: PulseAuthor?
    @State private var draft = ""
    @FocusState private var composing: Bool

    init(pulseID: UUID, config: PulseConfig, sync: PulseSync) {
        self.config = config
        self.sync = sync
        _parents = Query(filter: #Predicate { $0.id == pulseID })
        _replies = Query(filter: #Predicate { $0.pulseId == pulseID },
                         sort: \ReplyEntity.createdAt, order: .forward)
    }

    private var pulse: PulseEntity? { parents.first }

    var body: some View {
        Group {
            if let pulse {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        PulseSpineRow(
                            pulse: pulse, author: parentAuthor, currentUserID: config.currentUserID,
                            forceExpanded: true,
                            onReact: { emoji in Task { try? await sync.react(pulseID: pulse.id, emoji: emoji) } },
                            onReply: { composing = true }
                        )
                        if !replies.isEmpty {
                            Divider().padding(.horizontal, 12)
                            ForEach(replies) { reply in
                                PulseReplyRow(reply: reply, config: config)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                .safeAreaInset(edge: .bottom) { replyBar(pulse) }
                .task(id: pulse.userId) { parentAuthor = await config.authorResolver.author(for: pulse.userId) }
                .task { await sync.loadReplies(pulseID: pulse.id) }
                .onAppear { PulseMediaBox.configure(baseURL: config.baseURL, tokenProvider: config.tokenProvider) }
            } else {
                ProgressView()
            }
        }
        .pulseInlineNavTitle("Pulse")
    }

    @ViewBuilder
    private func replyBar(_ pulse: PulseEntity) -> some View {
        HStack(spacing: 10) {
            TextField("Leave a reply…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .focused($composing)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .pulseGlassPane(20)
            Button {
                let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return }
                draft = ""; composing = false
                Task { try? await sync.reply(pulseID: pulse.id, text: text) }
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 30))
            }
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.bar)
    }
}

/// One reply row — light: avatar + name + text + time. No nested thread.
struct PulseReplyRow: View {
    let reply: ReplyEntity
    let config: PulseConfig
    @State private var author: PulseAuthor?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            PulseAvatar(author: author, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(author?.displayName ?? "…").font(.system(size: 14, weight: .semibold))
                    Text(relativeTime(reply.createdAt)).font(.caption2).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                if !reply.text.isEmpty { Text(reply.text).font(.system(size: 15)) }
                if let e = reply.emoji, !e.isEmpty, reply.text.isEmpty { Text(e).font(.system(size: 28)) }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: reply.userId) { author = await config.authorResolver.author(for: reply.userId) }
    }

    private func relativeTime(_ ms: Int64) -> String {
        Date(timeIntervalSince1970: TimeInterval(ms) / 1000).formatted(.relative(presentation: .numeric))
    }
}
