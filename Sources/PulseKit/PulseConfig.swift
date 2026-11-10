import Foundation

/// Display identity for a pulse author. PulseKit only knows `userId` (mvPulse
/// never denormalises profile); the host resolves names/avatars from its own
/// roster (in a host app: the contact store + ProfileKit). Keeps PulseKit
/// profile-agnostic.
public struct PulseAuthor: Sendable, Hashable {
    public let userID: UUID
    public let displayName: String
    public let avatarRef: String?
    public init(userID: UUID, displayName: String, avatarRef: String? = nil) {
        self.userID = userID
        self.displayName = displayName
        self.avatarRef = avatarRef
    }
}

/// The host's hook for turning a `userId` into display identity. Sendable +
/// async so the host can hit its own actor-isolated roster.
public protocol PulseAuthorResolving: Sendable {
    func author(for userID: UUID) async -> PulseAuthor?
}

/// Everything PulseKit needs from the host. A `Sendable` value; the only
/// reference-ish member (`authorResolver`) is itself `Sendable`.
public struct PulseConfig: Sendable {
    public let baseURL: URL
    public let tokenProvider: @Sendable () async -> String?
    public let authorResolver: any PulseAuthorResolving
    /// The signed-in user, so the UI can tell "mine" from "theirs" and resolve
    /// which reaction is the viewer's.
    public let currentUserID: UUID

    /// One-time resync gate. When this changes from the value the device last
    /// applied, PulseKit wipes its local feed cache and re-pulls from scratch on
    /// the next refresh. Bump it after a server-side bulk data change (history
    /// migration, backend cutover) that a delta sync can't reconcile. Empty
    /// (default) = never force a resync.
    public let resyncToken: String

    public init(baseURL: URL,
                currentUserID: UUID,
                tokenProvider: @escaping @Sendable () async -> String?,
                authorResolver: any PulseAuthorResolving,
                resyncToken: String = "") {
        self.baseURL = baseURL
        self.currentUserID = currentUserID
        self.tokenProvider = tokenProvider
        self.authorResolver = authorResolver
        self.resyncToken = resyncToken
    }

    /// The live transport for this config.
    public var transport: any PulseTransport {
        HTTPPulseTransport(baseURL: baseURL, tokenProvider: tokenProvider)
    }
}
