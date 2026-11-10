import Foundation

/// A media attachment on a pulse/reply (subset of chat's MessageMedia). `url` is
/// a direct/external URL (GIFs, lab fixtures); `ref` is a file id resolved to a
/// blob URL by the host. `width`/`height` drive aspect-correct layout.
public struct MediaRef: Codable, Sendable, Hashable {
    public let type: String   // image | gif | video | audio | file
    public let ref: String    // file id (may be empty for external media)
    public let url: String?   // direct URL (external media / fixtures)
    public let width: Int?
    public let height: Int?
    public let name: String?      // original filename (file kind)
    public let mimeType: String?  // for icon/extension hints
    public let duration: Double?  // seconds (video/audio)

    public init(type: String, ref: String = "", url: String? = nil, width: Int? = nil, height: Int? = nil,
                name: String? = nil, mimeType: String? = nil, duration: Double? = nil) {
        self.type = type; self.ref = ref; self.url = url; self.width = width; self.height = height
        self.name = name; self.mimeType = mimeType; self.duration = duration
    }
    public var isGif: Bool { type == "gif" }
    public var isVisual: Bool { type == "image" || type == "video" || isGif }
}

/// A fetched link preview (url-kind pulses).
public struct LinkPreview: Codable, Sendable, Hashable {
    public let url: String
    public let title: String?
    public let description: String?
    public let imageUrl: String?
    public let siteName: String?

    public init(url: String, title: String? = nil, description: String? = nil,
                imageUrl: String? = nil, siteName: String? = nil) {
        self.url = url; self.title = title; self.description = description
        self.imageUrl = imageUrl; self.siteName = siteName
    }
}

// Wire DTOs — the exact mvPulse contract. Value types, so `Sendable` is free;
// `public` types in a library are not implicitly Sendable, so we spell it out.
// All timestamps are epoch-millis (Int64); reactions are emoji → [userId].

/// A pulse as returned by the feed / create / edit endpoints.
public struct PulseDTO: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public let userId: UUID
    public let kind: String
    public let text: String
    public let emoji: String?
    public let mediaUrl: String?
    public let files: [MediaRef]?
    public let url: String?
    public let linkPreview: LinkPreview?
    public let reactions: [String: [UUID]]?
    public let expiresAt: Int64?
    public let audience: [UUID]?
    public let createdAt: Int64
    public let editedAt: Int64?
    /// Feed-only reply summary (nil on single-pulse responses).
    public let replyCount: Int?
    public let replyPreview: ReplyDTO?

    public init(id: UUID, userId: UUID, kind: String, text: String, emoji: String?,
                mediaUrl: String?, reactions: [String: [UUID]]?, expiresAt: Int64?,
                audience: [UUID]?, createdAt: Int64, editedAt: Int64?,
                replyCount: Int?, replyPreview: ReplyDTO?,
                files: [MediaRef]? = nil, url: String? = nil, linkPreview: LinkPreview? = nil) {
        self.id = id; self.userId = userId; self.kind = kind; self.text = text
        self.emoji = emoji; self.mediaUrl = mediaUrl; self.reactions = reactions
        self.expiresAt = expiresAt; self.audience = audience; self.createdAt = createdAt
        self.editedAt = editedAt; self.replyCount = replyCount; self.replyPreview = replyPreview
        self.files = files; self.url = url; self.linkPreview = linkPreview
    }
}

/// A reply on a pulse.
public struct ReplyDTO: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public let pulseId: UUID
    public let userId: UUID
    public let text: String
    public let emoji: String?
    public let reactions: [String: [UUID]]?
    public let createdAt: Int64
    public let editedAt: Int64?

    public init(id: UUID, pulseId: UUID, userId: UUID, text: String, emoji: String?,
                reactions: [String: [UUID]]?, createdAt: Int64, editedAt: Int64?) {
        self.id = id; self.pulseId = pulseId; self.userId = userId; self.text = text
        self.emoji = emoji; self.reactions = reactions; self.createdAt = createdAt; self.editedAt = editedAt
    }
}

/// One pull-feed page.
public struct FeedDTO: Codable, Sendable {
    public let pulses: [PulseDTO]
    public let syncTs: Int64
    public let hasMore: Bool
    public let deletedIds: [UUID]?

    public init(pulses: [PulseDTO], syncTs: Int64, hasMore: Bool, deletedIds: [UUID]?) {
        self.pulses = pulses; self.syncTs = syncTs; self.hasMore = hasMore; self.deletedIds = deletedIds
    }
}

/// The result of a reaction toggle (pulse or reply).
public struct ReactionDTO: Codable, Sendable {
    public let pulseId: UUID
    public let replyId: UUID?
    public let emoji: String
    public let reactions: [String: [UUID]]
    public let action: String // add | remove | swap
    public let ts: Int64

    public init(pulseId: UUID, replyId: UUID?, emoji: String, reactions: [String: [UUID]], action: String, ts: Int64) {
        self.pulseId = pulseId; self.replyId = replyId; self.emoji = emoji
        self.reactions = reactions; self.action = action; self.ts = ts
    }
}

/// The reply list for a pulse.
public struct RepliesDTO: Codable, Sendable {
    public let pulseId: UUID
    public let replies: [ReplyDTO]

    public init(pulseId: UUID, replies: [ReplyDTO]) {
        self.pulseId = pulseId; self.replies = replies
    }
}

/// Uploaded-blob metadata.
public struct FileDTO: Codable, Sendable {
    public let id: UUID
    public let mimeType: String
    public let sizeBytes: Int64
    public let url: String
    public init(id: UUID, mimeType: String, sizeBytes: Int64, url: String) {
        self.id = id; self.mimeType = mimeType; self.sizeBytes = sizeBytes; self.url = url
    }
}

/// The mark-seen watermark.
public struct SeenDTO: Codable, Sendable {
    public let pulseLastSeenAt: Int64
    public init(pulseLastSeenAt: Int64) { self.pulseLastSeenAt = pulseLastSeenAt }
}

/// One audience candidate from the server: an owner id plus their identity
/// (name + optional base64 avatar) from the synced people directory.
public struct PulseContact: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public let name: String
    public let avatar: String?
    public init(id: UUID, name: String, avatar: String? = nil) {
        self.id = id; self.name = name; self.avatar = avatar
    }
}

/// The caller's contacts — audience candidates for scoping a pulse. Names now
/// ride the social graph, so the client can label them without its own resolver.
public struct ContactsDTO: Codable, Sendable {
    public let contacts: [PulseContact]
    public init(contacts: [PulseContact]) { self.contacts = contacts }
}

/// Batch status-line request: the users whose latest visible pulse to fetch.
public struct LatestPulsesBody: Codable, Sendable {
    public let userIds: [UUID]
    public init(userIds: [UUID]) { self.userIds = userIds }
}

/// Each requested user's latest visible pulse, keyed by user id string. Users
/// with no visible pulse are omitted.
public struct LatestPulsesDTO: Codable, Sendable {
    public let latest: [String: PulseDTO]
    public init(latest: [String: PulseDTO]) { self.latest = latest }
}

public extension PulseDTO {
    /// A one-line summary for a status line / conversation-card pulse line —
    /// the text if present, else a kind-appropriate label. Hosts render statuses
    /// identically via this.
    var statusPreview: String {
        if !text.isEmpty { return text }
        if let e = emoji, !e.isEmpty { return e }
        switch kind {
        case "image", "gallery": return "📷 Photo"
        case "video":            return "🎬 Video"
        case "audio":            return "🎤 Audio"
        case "file":             return "📄 File"
        case "url":              return "🔗 Link"
        default:                 return "…"
        }
    }
}

// --- request bodies ---

public struct CreatePulseBody: Codable, Sendable {
    public var text: String
    public var kind: String
    public var emoji: String?
    public var mediaUrl: String?
    public var files: [MediaRef]?
    public var url: String?
    public var expiresIn: Int?
    public var audience: [UUID]?
    public init(text: String, kind: String = "text", emoji: String? = nil,
                mediaUrl: String? = nil, files: [MediaRef]? = nil, url: String? = nil,
                expiresIn: Int? = nil, audience: [UUID]? = nil) {
        self.text = text; self.kind = kind; self.emoji = emoji
        self.mediaUrl = mediaUrl; self.files = files; self.url = url
        self.expiresIn = expiresIn; self.audience = audience
    }
}

public struct EditBody: Codable, Sendable {
    public var text: String
    public var emoji: String?
    public init(text: String, emoji: String? = nil) { self.text = text; self.emoji = emoji }
}

public struct ReactBody: Codable, Sendable {
    public var emoji: String
    public init(emoji: String) { self.emoji = emoji }
}

public struct ReplyBody: Codable, Sendable {
    public var text: String
    public var emoji: String?
    public var files: [MediaRef]?
    public init(text: String, emoji: String? = nil, files: [MediaRef]? = nil) {
        self.text = text; self.emoji = emoji; self.files = files
    }
}

public struct ExpiryBody: Codable, Sendable {
    public var expiresIn: Int?
    public init(expiresIn: Int?) { self.expiresIn = expiresIn }
}
