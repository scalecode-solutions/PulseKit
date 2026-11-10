import Foundation
import Observation

/// Single source of truth for the viewer's audience candidates — the contacts
/// they may scope a pulse to. Async-loaded from the pulse backend, it exposes an
/// explicit load state so the picker shows loading / empty / error *honestly*
/// instead of a bare empty list (a failed fetch must not look like "no
/// contacts"). Because it's a reference type the picker *observes* — rather than
/// a by-value snapshot passed into a sheet — a load that finishes after the
/// picker is on screen still re-renders it. That removes the presentation race
/// where contacts only appeared after an unrelated state change.
@MainActor
@Observable
final class PulseContactsStore {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded([AudienceContact])
        case failed(String)
    }

    private(set) var state: LoadState = .idle

    private let transport: any PulseTransport
    private var task: Task<Void, Never>?

    init(transport: any PulseTransport) { self.transport = transport }

    /// Load once. Idempotent while loading or already loaded; a prior failure is
    /// left for an explicit `reload()` (the picker surfaces a Retry).
    func loadIfNeeded() {
        if case .idle = state { load() }
    }

    /// Force a fresh fetch (Retry, or pull-to-refresh).
    func reload() { load() }

    private func load() {
        task?.cancel()
        state = .loading
        task = Task { [transport] in
            do {
                let fetched = try await transport.contacts()
                var resolved: [AudienceContact] = []
                for c in fetched {
                    // Name rides the social edge; fall back to the host author
                    // resolver, then a short id, only when the edge carried none.
                    let name = c.name.isEmpty
                        ? (await PulseAuthorBox.resolve(c.id)?.displayName
                            ?? "Member \(c.id.uuidString.prefix(8))")
                        : c.name
                    resolved.append(AudienceContact(id: c.id, name: name, avatarRef: c.avatar))
                }
                if Task.isCancelled { return }
                state = .loaded(resolved)
            } catch is CancellationError {
                // Superseded by a newer load — leave the state to that task.
            } catch {
                if Task.isCancelled { return }
                state = .failed(Self.message(for: error))
            }
        }
    }

    private static func message(for error: Error) -> String {
        if let e = error as? PulseTransportError {
            switch e {
            case .notAuthenticated:   return "You're signed out — sign in and try again."
            case .badResponse(let s): return "Couldn't load contacts (HTTP \(s))."
            case .decoding:           return "Unexpected response from the server."
            case .network(let m):     return "Network error: \(m)"
            }
        }
        return "Couldn't load contacts."
    }
}
