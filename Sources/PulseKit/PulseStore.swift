import Foundation
import SwiftData

/// PulseKit's persistence façade. **Main-actor confined** — the lesson from the
/// tracker SPM's integration: the main `ModelContext` is the only safe place to
/// touch SwiftData. Network I/O is `async` and hops off-main inside the
/// transport; everything here stays on the main actor. No background
/// `ModelActor`, no `@unchecked Sendable` promises.
@MainActor
public final class PulseStore {
    public let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    /// On-disk store (the app path).
    public init() {
        let schema = Schema([PulseEntity.self, ReplyEntity.self, SyncCursorEntity.self])
        let config = ModelConfiguration("PulseKit", schema: schema)
        do {
            container = try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("PulseKit: failed to open store: \(error)")
        }
    }

    /// In-memory store (tests / previews).
    public init(inMemory: Bool) {
        let schema = Schema([PulseEntity.self, ReplyEntity.self, SyncCursorEntity.self])
        let config = ModelConfiguration("PulseKit", schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            container = try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("PulseKit: failed to open in-memory store: \(error)")
        }
    }

    // MARK: - Cursor

    public func cursor() -> Int64 {
        let fetch = FetchDescriptor<SyncCursorEntity>(predicate: #Predicate { $0.key == "feed" })
        return (try? context.fetch(fetch).first?.syncTs) ?? 0
    }

    public func setCursor(_ ts: Int64) {
        let fetch = FetchDescriptor<SyncCursorEntity>(predicate: #Predicate { $0.key == "feed" })
        if let existing = try? context.fetch(fetch).first {
            existing.syncTs = ts
        } else {
            context.insert(SyncCursorEntity(syncTs: ts))
        }
    }

    // MARK: - Seen cursor + unread

    /// The "last looked at the feed" timestamp (epoch millis). Foreign pulses
    /// newer than this are unread.
    public func lastSeenAt() -> Int64 {
        let fetch = FetchDescriptor<SyncCursorEntity>(predicate: #Predicate { $0.key == "seen" })
        return (try? context.fetch(fetch).first?.syncTs) ?? 0
    }

    public func setLastSeenAt(_ ts: Int64) {
        let fetch = FetchDescriptor<SyncCursorEntity>(predicate: #Predicate { $0.key == "seen" })
        if let existing = try? context.fetch(fetch).first {
            existing.syncTs = ts
        } else {
            context.insert(SyncCursorEntity(key: "seen", syncTs: ts))
        }
    }

    /// The newest pulse NOT authored by `me` (its createdAt), or nil if none —
    /// compared against `lastSeenAt()` for the quiet unread dot.
    public func newestForeignCreatedAt(excluding me: UUID) -> Int64? {
        var fetch = FetchDescriptor<PulseEntity>(
            predicate: #Predicate { $0.userId != me },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        fetch.fetchLimit = 1
        return try? context.fetch(fetch).first?.createdAt
    }

    // MARK: - Delta application

    /// Apply one feed page: upsert pulses, drop tombstoned ids, advance cursor.
    /// Tombstones are applied BEFORE upserts so a delete+repost in the same page
    /// nets to "present" (mirrors the client's existing ordering).
    public func applyFeedPage(_ page: FeedDTO) {
        for id in page.deletedIds ?? [] { deletePulse(id: id) }
        for dto in page.pulses { upsert(dto) }
        setCursor(page.syncTs)
        save()
    }

    public func upsert(_ dto: PulseDTO) {
        let id = dto.id
        let fetch = FetchDescriptor<PulseEntity>(predicate: #Predicate { $0.id == id })
        let reactions = ReactionCodec.encode(dto.reactions)
        let preview = dto.replyPreview
        let filesData = dto.files.flatMap { try? JSONEncoder().encode($0) }
        let lpData = dto.linkPreview.flatMap { try? JSONEncoder().encode($0) }
        if let e = try? context.fetch(fetch).first {
            e.kind = dto.kind; e.text = dto.text; e.emoji = dto.emoji; e.mediaUrl = dto.mediaUrl
            e.url = dto.url; e.filesData = filesData; e.linkPreviewData = lpData
            e.reactionsData = reactions; e.expiresAt = dto.expiresAt; e.audience = dto.audience
            e.editedAt = dto.editedAt; e.replyCount = dto.replyCount ?? e.replyCount
            e.replyPreviewText = preview?.text; e.replyPreviewEmoji = preview?.emoji
            e.replyPreviewUserId = preview?.userId
        } else {
            context.insert(PulseEntity(
                id: dto.id, userId: dto.userId, kind: dto.kind, text: dto.text, emoji: dto.emoji,
                mediaUrl: dto.mediaUrl, reactionsData: reactions, expiresAt: dto.expiresAt,
                audience: dto.audience, createdAt: dto.createdAt, editedAt: dto.editedAt,
                replyCount: dto.replyCount ?? 0,
                replyPreviewText: preview?.text, replyPreviewEmoji: preview?.emoji,
                replyPreviewUserId: preview?.userId,
                url: dto.url, filesData: filesData, linkPreviewData: lpData))
        }
    }

    /// Patch only the reaction map on an existing pulse (from a react echo),
    /// without touching its other fields. No-op if the pulse isn't local.
    public func patchPulseReactions(id: UUID, _ reactions: [String: [UUID]]) {
        let fetch = FetchDescriptor<PulseEntity>(predicate: #Predicate { $0.id == id })
        if let e = try? context.fetch(fetch).first {
            e.reactionsData = ReactionCodec.encode(reactions)
        }
    }

    public func deletePulse(id: UUID) {
        let fetch = FetchDescriptor<PulseEntity>(predicate: #Predicate { $0.id == id })
        if let e = try? context.fetch(fetch).first { context.delete(e) }
    }

    /// Upsert a pulse's replies (from the replies endpoint or a reply echo).
    public func upsertReplies(_ replies: [ReplyDTO], for pulseID: UUID) {
        let pf = FetchDescriptor<PulseEntity>(predicate: #Predicate { $0.id == pulseID })
        let parent = try? context.fetch(pf).first
        for r in replies {
            let rid = r.id
            let f = FetchDescriptor<ReplyEntity>(predicate: #Predicate { $0.id == rid })
            if let e = try? context.fetch(f).first {
                e.text = r.text; e.emoji = r.emoji; e.editedAt = r.editedAt
                e.reactionsData = ReactionCodec.encode(r.reactions)
            } else {
                let e = ReplyEntity(id: r.id, pulseId: r.pulseId, userId: r.userId, text: r.text,
                                    emoji: r.emoji, reactionsData: ReactionCodec.encode(r.reactions),
                                    createdAt: r.createdAt, editedAt: r.editedAt)
                e.pulse = parent
                context.insert(e)
            }
        }
        save()
    }

    public func oldestCreatedAt() -> Int64? {
        var fetch = FetchDescriptor<PulseEntity>(sortBy: [SortDescriptor(\.createdAt, order: .forward)])
        fetch.fetchLimit = 1
        return try? context.fetch(fetch).first?.createdAt
    }

    public func save() {
        guard context.hasChanges else { return }
        try? context.save()
    }

    /// Wipe the local feed cache and the feed cursor so the next `refresh()`
    /// re-pulls everything from the server (since = nil). Used by resync after a
    /// server-side bulk data change (migration / cutover) that a delta sync
    /// can't reconcile — e.g. hard-deleted rows that left no tombstone. The
    /// "seen" cursor is preserved so unread state survives the rebuild.
    public func reset() {
        try? context.delete(model: PulseEntity.self)
        try? context.delete(model: ReplyEntity.self)
        try? context.delete(model: SyncCursorEntity.self, where: #Predicate { $0.key == "feed" })
        save()
    }

    /// Delete everything PulseKit keeps on this device: the feed, replies, and
    /// every cursor (the feed position and the "seen" mark). For sign-out, so
    /// nothing from one account is left on disk for the next. Unlike `reset()`,
    /// nothing survives.
    public func wipeAll() {
        try? context.delete(model: PulseEntity.self)
        try? context.delete(model: ReplyEntity.self)
        try? context.delete(model: SyncCursorEntity.self)
        try? context.save()
    }

    /// Sign-out helper for a host that holds no live store: opens the on-disk
    /// store and wipes it. Call it on the main actor when the user signs out.
    public static func wipeOnDisk() {
        PulseStore().wipeAll()
    }
}
