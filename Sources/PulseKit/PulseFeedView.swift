import SwiftUI
import SwiftData

/// The Pulse tab page — PulseKit's public entry point. Den-style: the host drops
/// this in with a `PulseConfig` and PulseKit owns everything behind it (network,
/// its own SwiftData store, sync, UI). `embedded` lets the host's nav chrome
/// wrap it. The card/spine look is ported from the host app's PulseHub.
public struct PulseFeedView: View {
    private let config: PulseConfig
    private let embedded: Bool
    /// Optional host avatar renderer. When provided, PulseKit renders it wherever
    /// avatars go and `PulseAuthor.avatarRef` becomes host-interpreted (e.g. a
    /// The host app photoRef). Absent, the built-in base64/initials avatar is used.
    /// It's a `@MainActor` view-builder, so it rides here (MainActor) rather than
    /// on the `Sendable` `PulseConfig`.
    private let avatarView: ((PulseAuthor, CGFloat) -> AnyView)?

    public init(config: PulseConfig, embedded: Bool = false,
                avatarView: ((PulseAuthor, CGFloat) -> AnyView)? = nil) {
        self.config = config
        self.embedded = embedded
        self.avatarView = avatarView
        let store = PulseStore()
        _store = State(initialValue: store)
        _sync = State(initialValue: PulseSync(config: config, store: store))
    }

    /// Test/preview seam.
    public init(config: PulseConfig, store: PulseStore, transport: any PulseTransport,
                embedded: Bool = false,
                avatarView: ((PulseAuthor, CGFloat) -> AnyView)? = nil) {
        self.config = config
        self.embedded = embedded
        self.avatarView = avatarView
        _store = State(initialValue: store)
        _sync = State(initialValue: PulseSync(transport: transport, store: store))
    }

    @State private var store: PulseStore
    @State private var sync: PulseSync

    public var body: some View {
        PulseFeedScroll(config: config, sync: sync)
            .modelContainer(store.container)
            .onAppear {
                PulseAuthorBox.configure(config.authorResolver)
                PulseAvatarBox.configure(avatarView)
                PulseMediaBox.configure(baseURL: config.baseURL, tokenProvider: config.tokenProvider)
            }
    }
}

private struct PulseFeedScroll: View {
    let config: PulseConfig
    let sync: PulseSync

    @Query(sort: \PulseEntity.createdAt, order: .reverse) private var pulses: [PulseEntity]
    @State private var me: PulseAuthor?
    @State private var detailPulseID: UUID?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if let err = sync.lastError {
                    Text(err).font(.footnote).foregroundStyle(.red).padding(.horizontal, 16)
                }
                if pulses.isEmpty {
                    emptyOrLoading
                } else {
                    feedContent
                }
            }
            .padding(.bottom, 40)
        }
        // The composer is PINNED below the header — it never scrolls with the
        // feed (the host app: PulseHubFeed.safeAreaInset(edge: .top)).
        .safeAreaInset(edge: .top, spacing: 0) {
            PulseComposerBar(me: me, transport: config.transport) { body in
                Task { try? await sync.post(body) }
            }
            .padding(.bottom, 8)
        }
        .refreshable { await sync.refresh() }
        .navigationDestination(item: $detailPulseID) { id in
            PulseDetailView(pulseID: id, config: config, sync: sync)
                // The NavigationStack hoists this above the feed's modelContainer,
                // so re-attach it or the detail's @Query returns nothing.
                .modelContainer(sync.container)
        }
        .task {
            me = await config.authorResolver.author(for: config.currentUserID)
            await sync.refresh()
            await sync.markSeen()
        }
    }

    @ViewBuilder
    private var emptyOrLoading: some View {
        if sync.isLoading {
            ProgressView().padding(.top, 60)
        } else {
            VStack(spacing: 6) {
                Text("Nothing yet").font(.headline)
                Text("Whatcha doin'? Leave the first pulse.").font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(.top, 60)
        }
    }

    @ViewBuilder
    private var feedContent: some View {
        ForEach(sections, id: \.id) { section in
            PulseDaySeparator(label: section.label)
            ForEach(section.pulses) { pulse in
                PulseRowContainer(pulse: pulse, config: config, sync: sync,
                                  onOpenDetail: { detailPulseID = pulse.id })
                    .id(pulse.id)
            }
        }
        if !sync.isLoading {
            PulseFeedEnd().padding(.top, 8)
        }
    }

    // Day-group the query results (newest first).
    private var sections: [DaySection] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: pulses) { p in
            cal.startOfDay(for: Date(timeIntervalSince1970: Double(p.createdAt) / 1000))
        }
        return grouped.sorted { $0.key > $1.key }.map { day, items in
            DaySection(id: day.timeIntervalSince1970, label: Self.dayLabel(day),
                       pulses: items.sorted { $0.createdAt > $1.createdAt })
        }
    }

    static func dayLabel(_ date: Date, now: Date = Date()) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        let f = DateFormatter()
        f.dateFormat = cal.isDate(date, equalTo: now, toGranularity: .year) ? "MMM d" : "MMM d, yyyy"
        return f.string(from: date)
    }

    private struct DaySection: Identifiable {
        let id: Double
        let label: String
        let pulses: [PulseEntity]
    }
}

/// Resolves the author for a row, then renders the ported spine row and wires
/// its callbacks into the sync engine.
private struct PulseRowContainer: View {
    let pulse: PulseEntity
    let config: PulseConfig
    let sync: PulseSync
    let onOpenDetail: () -> Void
    @State private var author: PulseAuthor?
    @State private var editing = false
    @State private var editDraft = ""
    @State private var confirmingDelete = false

    var body: some View {
        PulseSpineRow(
            pulse: pulse,
            author: author,
            currentUserID: config.currentUserID,
            onReact: { emoji in Task { try? await sync.react(pulseID: pulse.id, emoji: emoji) } },
            onReply: onOpenDetail,
            onAction: handle
        )
        .task(id: pulse.userId) { author = await config.authorResolver.author(for: pulse.userId) }
        .sheet(isPresented: $editing) { editSheet }
        .confirmationDialog("Delete this pulse?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { try? await sync.delete(pulseID: pulse.id) } }
        }
    }

    private func handle(_ action: PulseCardAction) {
        switch action {
        case .copy:
            UIPasteboard.general.string = pulse.text
        case .edit:
            editDraft = pulse.text; editing = true
        case .delete:
            confirmingDelete = true
        case .setExpiry(let seconds):
            Task { try? await sync.setExpiry(pulseID: pulse.id, seconds: seconds) }
        }
    }

    private var editSheet: some View {
        NavigationStack {
            TextEditor(text: $editDraft).font(.system(size: 18)).padding(8)
                .pulseInlineNavTitle("Edit pulse")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { editing = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            let t = editDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                            editing = false
                            if !t.isEmpty { Task { try? await sync.edit(pulseID: pulse.id, text: t, emoji: pulse.emoji) } }
                        }
                    }
                }
        }
        .presentationDetents([.medium])
    }
}

/// Inline, non-pinned day separator pill. Ported from PulseHubFeedSection.
struct PulseDaySeparator: View {
    let label: String
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.6)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .pulseGlassPane(100)
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }
}

/// Terminal "all caught up" cell — the finishable-feed gift.
struct PulseFeedEnd: View {
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "checkmark.circle").font(.system(size: 18)).foregroundStyle(.secondary)
            Text("You're all caught up").font(.footnote).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 16)
    }
}
