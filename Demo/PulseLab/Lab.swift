import Foundation
import PulseKit

/// Which backend PulseLab talks to. Auth goes to mvServer (WebSocket via MvAuth);
/// the feed goes to mvPulse (HTTP via PulseKit). Same credentials, two services.
enum LabServer: String, CaseIterable, Identifiable, Sendable {
    case production = "Production"
    case local = "Local"

    var id: String { rawValue }

    /// mvServer WebSocket endpoint MvAuth logs in against.
    var authWS: URL {
        switch self {
        case .production: URL(string: "wss://api.mvchat.app/v0/ws")!
        case .local:      URL(string: "ws://localhost:6070/v0/ws")!
        }
    }

    /// mvPulse base URL PulseKit pulls the feed from.
    var pulseBaseURL: URL {
        switch self {
        case .production: URL(string: "https://pulse.mvchat.app")!
        case .local:      URL(string: "http://localhost:6090")!
        }
    }
}

/// Resolves a pulse author's id → identity (name + avatar). The signed-in user
/// comes from the login profile; everyone else is resolved from the contacts
/// feed, which carries name + base64 avatar synced through the social graph's
/// people directory (mvServer → mvPulse). Fetched once and memoized; ids not in
/// the directory fall back to a short label. An actor so the lazy cache is
/// race-free under concurrent lookups.
actor LabRoster: PulseAuthorResolving {
    private let myID: String
    private let myName: String
    private let transport: any PulseTransport
    private var contacts: [UUID: PulseContact] = [:]
    private var loadTask: Task<Void, Never>?

    init(myID: String, myName: String, transport: any PulseTransport) {
        self.myID = myID
        self.myName = myName
        self.transport = transport
    }

    func author(for userID: UUID) async -> PulseAuthor? {
        await loadIfNeeded()
        let isSelf = userID.uuidString.lowercased() == myID.lowercased()
        if let c = contacts[userID] {
            // Self keeps its login-profile name; everyone else uses the directory.
            // Avatar comes from the directory in both cases.
            let name = isSelf ? myName : (c.name.isEmpty ? "Member \(userID.uuidString.prefix(8))" : c.name)
            return PulseAuthor(userID: userID, displayName: name, avatarRef: c.avatar)
        }
        if isSelf { return PulseAuthor(userID: userID, displayName: myName) }
        let short = String(userID.uuidString.prefix(8))
        return PulseAuthor(userID: userID, displayName: "Member \(short)")
    }

    /// Fetch the directory once: contacts (others) + me (self's own entry, since
    /// the contacts list excludes self). Concurrent callers await the same task.
    private func loadIfNeeded() async {
        if let task = loadTask { await task.value; return }
        let task = Task { await self.fetchContacts() }
        loadTask = task
        await task.value
    }

    private func fetchContacts() async {
        if let fetched = try? await transport.contacts() {
            for c in fetched { contacts[c.id] = c }
        }
        if let me = try? await transport.me() {
            contacts[me.id] = me
        }
    }
}
