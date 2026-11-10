import Foundation
import SwiftData

// SwiftData persistence models — PulseKit owns its own store (its own SQLite
// file), fully isolated from the host's GRDB (chat) and any other SwiftData
// container. @Model classes are reference types and are NOT Sendable; they live
// only on the main actor (see PulseStore / @MainActor), so they never cross an
// isolation boundary. Reactions are stored as JSON in `reactionsData` (a blob,
// like the server's head) and projected to a typed dict on read.

@Model
public final class PulseEntity {
    @Attribute(.unique) public var id: UUID
    public var userId: UUID
    public var kind: String
    public var text: String
    public var emoji: String?
    public var mediaUrl: String?
    public var url: String?
    public var filesData: Data?
    public var linkPreviewData: Data?
    public var reactionsData: Data?
    public var expiresAt: Int64?
    public var audience: [UUID]?
    public var createdAt: Int64
    public var editedAt: Int64?
    public var replyCount: Int
    // Latest-reply preview (for the inline reply-preview row). Author resolves
    // via the host like any other userId.
    public var replyPreviewText: String?
    public var replyPreviewEmoji: String?
    public var replyPreviewUserId: UUID?
    @Relationship(deleteRule: .cascade, inverse: \ReplyEntity.pulse)
    public var replies: [ReplyEntity]

    public init(id: UUID, userId: UUID, kind: String, text: String, emoji: String?,
                mediaUrl: String?, reactionsData: Data?, expiresAt: Int64?,
                audience: [UUID]?, createdAt: Int64, editedAt: Int64?, replyCount: Int,
                replyPreviewText: String? = nil, replyPreviewEmoji: String? = nil,
                replyPreviewUserId: UUID? = nil,
                url: String? = nil, filesData: Data? = nil, linkPreviewData: Data? = nil) {
        self.id = id; self.userId = userId; self.kind = kind; self.text = text
        self.emoji = emoji; self.mediaUrl = mediaUrl; self.reactionsData = reactionsData
        self.expiresAt = expiresAt; self.audience = audience; self.createdAt = createdAt
        self.editedAt = editedAt; self.replyCount = replyCount
        self.replyPreviewText = replyPreviewText; self.replyPreviewEmoji = replyPreviewEmoji
        self.replyPreviewUserId = replyPreviewUserId
        self.url = url; self.filesData = filesData; self.linkPreviewData = linkPreviewData
        self.replies = []
    }
}

@Model
public final class ReplyEntity {
    @Attribute(.unique) public var id: UUID
    public var pulseId: UUID
    public var userId: UUID
    public var text: String
    public var emoji: String?
    public var reactionsData: Data?
    public var createdAt: Int64
    public var editedAt: Int64?
    public var pulse: PulseEntity?

    public init(id: UUID, pulseId: UUID, userId: UUID, text: String, emoji: String?,
                reactionsData: Data?, createdAt: Int64, editedAt: Int64?) {
        self.id = id; self.pulseId = pulseId; self.userId = userId; self.text = text
        self.emoji = emoji; self.reactionsData = reactionsData; self.createdAt = createdAt
        self.editedAt = editedAt
    }
}

/// Single-row persisted feed cursor (the `syncTs` watermark), kept in the same
/// store as the data so it advances transactionally — the usual sync-kit
/// `SyncCursor` pattern.
@Model
public final class SyncCursorEntity {
    @Attribute(.unique) public var key: String
    public var syncTs: Int64
    public init(key: String = "feed", syncTs: Int64) { self.key = key; self.syncTs = syncTs }
}

// MARK: - Reaction blob <-> typed projection

enum ReactionCodec {
    static func encode(_ reactions: [String: [UUID]]?) -> Data? {
        guard let reactions, !reactions.isEmpty else { return nil }
        return try? JSONEncoder().encode(reactions)
    }
    static func decode(_ data: Data?) -> [String: [UUID]] {
        guard let data, let r = try? JSONDecoder().decode([String: [UUID]].self, from: data) else { return [:] }
        return r
    }
}

public extension PulseEntity {
    /// Typed reaction view (decoded from the stored blob).
    var reactions: [String: [UUID]] { ReactionCodec.decode(reactionsData) }
}

public extension ReplyEntity {
    var reactions: [String: [UUID]] { ReactionCodec.decode(reactionsData) }
}
