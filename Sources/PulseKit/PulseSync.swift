import Foundation
import Observation
import SwiftData

/// The driver: pull deltas from mvPulse into the local store, and route
/// mutations (post/react/reply/…) through the transport then reconcile locally.
///
/// `@MainActor` + `@Observable`: the UI observes `isLoading` / `lastError`, and
/// all SwiftData work runs on the main actor via `PulseStore`. Only the
/// transport awaits hop off-main. Coalesces concurrent refreshes (the cold-launch
/// scenePhase+auth race), the same trick a sync layer uses.
@MainActor
@Observable
public final class PulseSync {
    public private(set) var isLoading = false
    public private(set) var lastError: String?
    /// A quiet "there's new activity since you last looked" flag — no count. The
    /// host renders it as a dot on the Pulse tab. Recomputed on refresh + markSeen;
    /// pull-derived (no realtime, no push), per the ambient-glance design.
    public private(set) var hasUnread = false

    private let transport: any PulseTransport
    private let store: PulseStore
    private let currentUserID: UUID?
    private let resyncToken: String
    private var isRefreshing = false

    /// The SwiftData container backing this sync's store. Exposed so pushed
    /// screens (the detail view via `navigationDestination`, which the
    /// NavigationStack hoists above the feed's `.modelContainer`) can attach it
    /// — otherwise their `@Query` runs container-less and returns nothing.
    public var container: ModelContainer { store.container }

    public init(transport: any PulseTransport, store: PulseStore, currentUserID: UUID? = nil, resyncToken: String = "") {
        self.transport = transport
        self.store = store
        self.currentUserID = currentUserID
        self.resyncToken = resyncToken
    }

    public convenience init(config: PulseConfig, store: PulseStore) {
        self.init(transport: config.transport, store: store,
                  currentUserID: config.currentUserID, resyncToken: config.resyncToken)
    }

    /// Pull everything new since the persisted cursor, draining pages until the
    /// server reports no more (or the cursor stops advancing).
    public func refresh() async {
        if isRefreshing { return }
        isRefreshing = true
        isLoading = true
        defer { isRefreshing = false; isLoading = false }

        applyResyncIfNeeded()
        var since = store.cursor()
        do {
            while true {
                let page = try await transport.feed(since: since > 0 ? since : nil, before: nil, limit: nil)
                store.applyFeedPage(page)
                guard page.hasMore, page.syncTs > since else { break }
                since = page.syncTs
            }
            lastError = nil
            recomputeUnread()
        } catch is CancellationError {
            // Benign: the request was cancelled (task superseded or torn down by
            // SwiftUI). Not a real error — the next refresh covers it.
        } catch {
            lastError = describe(error)
        }
    }

    /// Page backward through history using the oldest local pulse as the
    /// `before` cursor (the client's `loadMoreFeed` semantics).
    public func loadMore() async {
        guard let before = store.oldestCreatedAt() else { return await refresh() }
        do {
            let page = try await transport.feed(since: nil, before: before, limit: nil)
            // Older pages carry no tombstones; just upsert.
            for dto in page.pulses { store.upsert(dto) }
            store.save()
            lastError = nil
        } catch is CancellationError {
            // Benign: the request was cancelled (task superseded or torn down by
            // SwiftUI). Not a real error — the next refresh covers it.
        } catch {
            lastError = describe(error)
        }
    }

    // MARK: - Mutations (optimistic-friendly: reconcile from the server echo)

    @discardableResult
    public func post(_ body: CreatePulseBody) async throws -> PulseDTO {
        let dto = try await transport.createPulse(body)
        store.upsert(dto); store.save()
        return dto
    }

    @discardableResult
    public func react(pulseID: UUID, emoji: String) async throws -> ReactionDTO {
        let res = try await transport.reactPulse(id: pulseID, ReactBody(emoji: emoji))
        // Patch the local reaction map from the authoritative server result —
        // only the reactions change; other fields are untouched.
        store.patchPulseReactions(id: pulseID, res.reactions)
        store.save()
        return res
    }

    public func delete(pulseID: UUID) async throws {
        try await transport.deletePulse(id: pulseID)
        store.deletePulse(id: pulseID); store.save()
    }

    @discardableResult
    public func edit(pulseID: UUID, text: String, emoji: String?) async throws -> PulseDTO {
        let dto = try await transport.editPulse(id: pulseID, EditBody(text: text, emoji: emoji))
        store.upsert(dto); store.save()
        return dto
    }

    public func setExpiry(pulseID: UUID, seconds: Int?) async throws {
        let dto = try await transport.setExpiry(id: pulseID, ExpiryBody(expiresIn: seconds))
        store.upsert(dto); store.save()
    }

    @discardableResult
    /// Load a pulse's replies into the local store (for the detail view).
    public func loadReplies(pulseID: UUID) async {
        do {
            let res = try await transport.replies(pulseId: pulseID, limit: nil)
            store.upsertReplies(res.replies, for: pulseID)
            lastError = nil
        } catch is CancellationError {
            // Benign: the request was cancelled (task superseded or torn down by
            // SwiftUI). Not a real error — the next refresh covers it.
        } catch {
            lastError = describe(error)
        }
    }

    public func reply(pulseID: UUID, text: String) async throws -> ReplyDTO {
        let r = try await transport.createReply(pulseId: pulseID, ReplyBody(text: text))
        store.upsertReplies([r], for: pulseID) // show it immediately
        await refresh()                        // pick up the parent's bumped replyCount/preview
        return r
    }

    public func markSeen() async {
        if let dto = try? await transport.markSeen() {
            store.setLastSeenAt(dto.pulseLastSeenAt)
            store.save()
            recomputeUnread()
        }
    }

    /// Manual full resync: wipe the local cache + cursor, then re-pull from the
    /// server. The escape hatch behind `resyncToken`'s automatic path — call it
    /// when the local feed has drifted from the server (e.g. after a backend
    /// data change a delta sync can't reconcile).
    public func resync() async {
        store.reset()
        await refresh()
    }

    // MARK: - helpers

    /// If the host bumped `resyncToken` since this device last applied it, wipe
    /// the local cache + cursor so the in-progress refresh re-pulls from scratch.
    /// Runs at most once per distinct token value (persisted in UserDefaults).
    private func applyResyncIfNeeded() {
        guard !resyncToken.isEmpty else { return }
        let key = "PulseKit.appliedResyncToken"
        if UserDefaults.standard.string(forKey: key) != resyncToken {
            store.reset()
            UserDefaults.standard.set(resyncToken, forKey: key)
        }
    }

    /// Pull-derived unread: any foreign pulse newer than the seen cursor. No count,
    /// no realtime — just "is there something new since you last looked."
    private func recomputeUnread() {
        guard let me = currentUserID else { hasUnread = false; return }
        let newest = store.newestForeignCreatedAt(excluding: me) ?? 0
        hasUnread = newest > store.lastSeenAt()
    }

    private func describe(_ error: Error) -> String {
        if let pe = error as? PulseError { return pe.description }
        return String(describing: error)
    }
}
