import Foundation
import Observation

/// Shared, observed cache of each user's latest visible pulse — the per-user
/// status line for conversation-card-style lists.
///
/// Mirrors a host presence/status manager (the host app's `PresenceStateManager`): the
/// host holds **one**, `refresh(for:)` batch-fetches the visible users' latest
/// pulses, and a card reads `latest(for:)` by user id — reactively, via
/// `@Observable`, so it re-renders when that user's status updates. Expired
/// pulses are dropped at read time, so a disappearing status fades on its own
/// (matching how `ConversationCardV2` already drops `status.isExpired`).
///
/// "My last pulse" is just `refresh(for: [myID])` + `latest(for: myID)`.
@MainActor
@Observable
public final class PulseStatusStore {
    public enum LoadState: Equatable { case idle, loading, loaded, failed(String) }
    public private(set) var state: LoadState = .idle

    private var cache: [UUID: PulseDTO] = [:]
    private let transport: any PulseTransport

    public init(transport: any PulseTransport) { self.transport = transport }

    /// The user's latest pulse, or nil if none / expired. Reactive: a view that
    /// reads this re-renders when the cache changes.
    public func latest(for userID: UUID) -> PulseDTO? {
        guard let p = cache[userID] else { return nil }
        if let exp = p.expiresAt, exp <= Self.nowMillis() { return nil } // fade on expire
        return p
    }

    /// Batch-fetch the latest pulse for these users (e.g. the visible cards' ids).
    /// Authoritative for exactly the requested set: a user that returns nothing is
    /// cleared, so a deleted/expired-out status disappears on the next refresh.
    public func refresh(for userIDs: [UUID]) async {
        if userIDs.isEmpty { return }
        state = .loading
        do {
            let fetched = try await transport.latestPulses(for: userIDs)
            for id in userIDs { cache[id] = fetched[id] } // nil ⇒ removes the key
            state = .loaded
        } catch {
            state = .failed(String(describing: error))
        }
    }

    private static func nowMillis() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
}
