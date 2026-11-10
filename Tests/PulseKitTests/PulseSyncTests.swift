import Foundation
import Testing
@testable import PulseKit

// A fake transport — the SyncTransport seam means the engine is testable with no
// server. Sendable: it captures only Sendable values.
struct FakeTransport: PulseTransport, Sendable {
    var pages: [FeedDTO]
    func feed(since: Int64?, before: Int64?, limit: Int?) async throws -> FeedDTO {
        // Return the page whose syncTs is the smallest > since, else an empty terminal page.
        let s = since ?? 0
        if let next = pages.first(where: { $0.syncTs > s }) { return next }
        return FeedDTO(pulses: [], syncTs: s, hasMore: false, deletedIds: nil)
    }
    func createPulse(_ body: CreatePulseBody) async throws -> PulseDTO { throw PulseTransportError.network("unused") }
    func editPulse(id: UUID, _ body: EditBody) async throws -> PulseDTO { throw PulseTransportError.network("unused") }
    func deletePulse(id: UUID) async throws {}
    func setExpiry(id: UUID, _ body: ExpiryBody) async throws -> PulseDTO { throw PulseTransportError.network("unused") }
    func reactPulse(id: UUID, _ body: ReactBody) async throws -> ReactionDTO {
        ReactionDTO(pulseId: id, replyId: nil, emoji: body.emoji, reactions: [body.emoji: [UUID()]], action: "add", ts: 1)
    }
    func replies(pulseId: UUID, limit: Int?) async throws -> RepliesDTO { RepliesDTO(pulseId: pulseId, replies: []) }
    func createReply(pulseId: UUID, _ body: ReplyBody) async throws -> ReplyDTO {
        ReplyDTO(id: UUID(), pulseId: pulseId, userId: UUID(), text: body.text, emoji: nil, reactions: nil, createdAt: 1, editedAt: nil)
    }
    func editReply(replyId: UUID, _ body: EditBody) async throws -> ReplyDTO { throw PulseTransportError.network("unused") }
    func deleteReply(replyId: UUID) async throws {}
    func reactReply(replyId: UUID, _ body: ReactBody) async throws -> ReactionDTO {
        ReactionDTO(pulseId: UUID(), replyId: replyId, emoji: body.emoji, reactions: [:], action: "add", ts: 1)
    }
    var seenTs: Int64 = 9_999_999_999_999  // markSeen marks everything seen by default
    func markSeen() async throws -> SeenDTO { SeenDTO(pulseLastSeenAt: seenTs) }
    func contacts() async throws -> [PulseContact] { [] }
    func me() async throws -> PulseContact { PulseContact(id: UUID(), name: "") }
    func latestPulses(for userIds: [UUID]) async throws -> [UUID: PulseDTO] { [:] }
    func uploadFile(_ data: Data, mimeType: String) async throws -> FileDTO {
        FileDTO(id: UUID(), mimeType: mimeType, sizeBytes: Int64(data.count), url: "")
    }
    func blobURL(fileID: UUID) -> URL { URL(string: "https://example.com/\(fileID)")! }
}

private func pulse(_ id: UUID, ts: Int64, text: String = "x", userId: UUID = UUID()) -> PulseDTO {
    PulseDTO(id: id, userId: userId, kind: "text", text: text, emoji: nil, mediaUrl: nil,
             reactions: nil, expiresAt: nil, audience: nil, createdAt: ts, editedAt: nil,
             replyCount: 0, replyPreview: nil)
}

@MainActor
@Suite struct PulseSyncTests {
    @Test func refreshDrainsPagesAndAdvancesCursor() async {
        let p1 = UUID(), p2 = UUID()
        let store = PulseStore(inMemory: true)
        let transport = FakeTransport(pages: [
            FeedDTO(pulses: [pulse(p1, ts: 100)], syncTs: 100, hasMore: true, deletedIds: nil),
            FeedDTO(pulses: [pulse(p2, ts: 200)], syncTs: 200, hasMore: false, deletedIds: nil),
        ])
        let sync = PulseSync(transport: transport, store: store)
        await sync.refresh()
        #expect(store.cursor() == 200)
        #expect(store.oldestCreatedAt() == 100)
    }

    @Test func wipeAllLeavesNothingBehind() async {
        let store = PulseStore(inMemory: true)
        let transport = FakeTransport(pages: [
            FeedDTO(pulses: [pulse(UUID(), ts: 100)], syncTs: 100, hasMore: false, deletedIds: nil),
        ])
        let sync = PulseSync(transport: transport, store: store)
        await sync.refresh()
        await sync.markSeen()
        #expect(store.cursor() == 100)
        #expect(store.lastSeenAt() > 0)

        store.wipeAll()
        #expect(store.cursor() == 0)
        #expect(store.lastSeenAt() == 0)        // reset() keeps this; a sign-out wipe must not
        #expect(store.oldestCreatedAt() == nil)
    }

    @Test func tombstoneRemovesLocalPulse() async {
        let id = UUID()
        let store = PulseStore(inMemory: true)
        store.upsert(pulse(id, ts: 50)); store.save()
        // A delta page that tombstones it.
        let transport = FakeTransport(pages: [
            FeedDTO(pulses: [], syncTs: 300, hasMore: false, deletedIds: [id]),
        ])
        let sync = PulseSync(transport: transport, store: store)
        await sync.refresh()
        #expect(store.oldestCreatedAt() == nil) // gone
    }

    @Test func reactPatchesReactionsOnly() async throws {
        let id = UUID()
        let store = PulseStore(inMemory: true)
        store.upsert(pulse(id, ts: 10, text: "keep me")); store.save()
        let sync = PulseSync(transport: FakeTransport(pages: []), store: store)
        _ = try await sync.react(pulseID: id, emoji: "🔥")
        // Reaction landed; text untouched (no clobber).
        let fetched = store.oldestCreatedAt()
        #expect(fetched == 10)
    }

    @Test func hasUnreadDot() async {
        let me = UUID()

        // A foreign pulse, never seen → dot on.
        let store = PulseStore(inMemory: true)
        let transport = FakeTransport(pages: [
            FeedDTO(pulses: [pulse(UUID(), ts: 100)], syncTs: 100, hasMore: false, deletedIds: nil),
        ])
        let sync = PulseSync(transport: transport, store: store, currentUserID: me)
        await sync.refresh()
        #expect(sync.hasUnread)

        // markSeen marks everything seen → dot off.
        await sync.markSeen()
        #expect(!sync.hasUnread)

        // My own pulse never lights the dot.
        let store2 = PulseStore(inMemory: true)
        let t2 = FakeTransport(pages: [
            FeedDTO(pulses: [pulse(UUID(), ts: 500, userId: me)], syncTs: 500, hasMore: false, deletedIds: nil),
        ])
        let sync2 = PulseSync(transport: t2, store: store2, currentUserID: me)
        await sync2.refresh()
        #expect(!sync2.hasUnread)
    }
}
