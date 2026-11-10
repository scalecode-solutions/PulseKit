import Foundation

/// The network boundary. A protocol so the sync engine + UI are testable with a
/// fake (no server), the usual transport seam.
public protocol PulseTransport: Sendable {
    func feed(since: Int64?, before: Int64?, limit: Int?) async throws -> FeedDTO
    func createPulse(_ body: CreatePulseBody) async throws -> PulseDTO
    func editPulse(id: UUID, _ body: EditBody) async throws -> PulseDTO
    func deletePulse(id: UUID) async throws
    func setExpiry(id: UUID, _ body: ExpiryBody) async throws -> PulseDTO
    func reactPulse(id: UUID, _ body: ReactBody) async throws -> ReactionDTO
    func replies(pulseId: UUID, limit: Int?) async throws -> RepliesDTO
    func createReply(pulseId: UUID, _ body: ReplyBody) async throws -> ReplyDTO
    func editReply(replyId: UUID, _ body: EditBody) async throws -> ReplyDTO
    func deleteReply(replyId: UUID) async throws
    func reactReply(replyId: UUID, _ body: ReactBody) async throws -> ReactionDTO
    func markSeen() async throws -> SeenDTO
    func contacts() async throws -> [PulseContact]
    /// The caller's own identity from the people directory (for the self-avatar).
    func me() async throws -> PulseContact
    /// Each user's latest visible pulse — the per-user status line for cards.
    /// "My last pulse" is `latestPulses(for: [me])`. Users with no visible pulse
    /// are absent from the result.
    func latestPulses(for userIds: [UUID]) async throws -> [UUID: PulseDTO]
    // Media blobs.
    func uploadFile(_ data: Data, mimeType: String) async throws -> FileDTO
    func blobURL(fileID: UUID) -> URL
}

/// REST transport against mvPulse. A value type whose members are all Sendable,
/// so it's `Sendable` with no `@unchecked`. The token provider is `@Sendable`
/// and `async` — the host supplies the current access token (e.g. from mvServer
/// auth); it's invoked off the caller's actor.
public struct HTTPPulseTransport: PulseTransport {
    public let baseURL: URL
    public let tokenProvider: @Sendable () async -> String?
    private let session: URLSession

    public init(baseURL: URL,
                tokenProvider: @escaping @Sendable () async -> String?,
                session: URLSession = .shared) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self.session = session
    }

    // MARK: - Pulses

    public func feed(since: Int64?, before: Int64?, limit: Int?) async throws -> FeedDTO {
        var q: [URLQueryItem] = []
        if let since { q.append(.init(name: "since", value: String(since))) }
        if let before { q.append(.init(name: "before", value: String(before))) }
        if let limit { q.append(.init(name: "limit", value: String(limit))) }
        return try await get("/v0/pulse/feed", query: q)
    }

    public func createPulse(_ body: CreatePulseBody) async throws -> PulseDTO {
        try await send("POST", "/v0/pulse", body: body)
    }

    public func editPulse(id: UUID, _ body: EditBody) async throws -> PulseDTO {
        try await send("PATCH", "/v0/pulse/\(id)", body: body)
    }

    public func deletePulse(id: UUID) async throws {
        try await sendNoContent("DELETE", "/v0/pulse/\(id)")
    }

    public func setExpiry(id: UUID, _ body: ExpiryBody) async throws -> PulseDTO {
        try await send("PUT", "/v0/pulse/\(id)/expiry", body: body)
    }

    public func reactPulse(id: UUID, _ body: ReactBody) async throws -> ReactionDTO {
        try await send("POST", "/v0/pulse/\(id)/reactions", body: body)
    }

    // MARK: - Replies

    public func replies(pulseId: UUID, limit: Int?) async throws -> RepliesDTO {
        var q: [URLQueryItem] = []
        if let limit { q.append(.init(name: "limit", value: String(limit))) }
        return try await get("/v0/pulse/\(pulseId)/replies", query: q)
    }

    public func createReply(pulseId: UUID, _ body: ReplyBody) async throws -> ReplyDTO {
        try await send("POST", "/v0/pulse/\(pulseId)/replies", body: body)
    }

    public func editReply(replyId: UUID, _ body: EditBody) async throws -> ReplyDTO {
        try await send("PATCH", "/v0/pulse/replies/\(replyId)", body: body)
    }

    public func deleteReply(replyId: UUID) async throws {
        try await sendNoContent("DELETE", "/v0/pulse/replies/\(replyId)")
    }

    public func reactReply(replyId: UUID, _ body: ReactBody) async throws -> ReactionDTO {
        try await send("POST", "/v0/pulse/replies/\(replyId)/reactions", body: body)
    }

    // MARK: - Seen

    public func markSeen() async throws -> SeenDTO {
        try await send("POST", "/v0/pulse/seen", body: EmptyBody())
    }

    public func contacts() async throws -> [PulseContact] {
        let res: ContactsDTO = try await get("/v0/pulse/contacts", query: [])
        return res.contacts
    }

    public func me() async throws -> PulseContact {
        try await get("/v0/pulse/me", query: [])
    }

    public func latestPulses(for userIds: [UUID]) async throws -> [UUID: PulseDTO] {
        if userIds.isEmpty { return [:] }
        let res: LatestPulsesDTO = try await send("POST", "/v0/pulse/latest",
                                                  body: LatestPulsesBody(userIds: userIds))
        var out: [UUID: PulseDTO] = [:]
        for (key, dto) in res.latest {
            if let id = UUID(uuidString: key) { out[id] = dto }
        }
        return out
    }

    // MARK: - Media blobs

    /// Upload raw bytes (POST /v0/pulse/files) → file metadata. The returned id
    /// is then referenced from a pulse/reply's `files`.
    public func uploadFile(_ data: Data, mimeType: String) async throws -> FileDTO {
        var req = URLRequest(url: baseURL.appendingPathComponent("/v0/pulse/files"))
        req.httpMethod = "POST"
        req.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        return try await perform(req)
    }

    /// The authed blob URL (GET /v0/pulse/files/{id}/blob). Display still needs an
    /// authed loader (Bearer) — AsyncImage can't add headers; that loader is a
    /// follow-up.
    public func blobURL(fileID: UUID) -> URL {
        baseURL.appendingPathComponent("/v0/pulse/files/\(fileID)/blob")
    }

    // MARK: - Plumbing

    private struct EmptyBody: Encodable {}

    private func get<Res: Decodable>(_ path: String, query: [URLQueryItem]) async throws -> Res {
        var comps = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        comps?.queryItems = query.isEmpty ? nil : query
        guard let url = comps?.url else { throw PulseTransportError.network("bad url \(path)") }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        return try await perform(req)
    }

    private func send<Body: Encodable, Res: Decodable>(_ method: String, _ path: String, body: Body) async throws -> Res {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        return try await perform(req)
    }

    private func sendNoContent(_ method: String, _ path: String) async throws {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = method
        _ = try await rawData(req)
    }

    private func perform<Res: Decodable>(_ request: URLRequest) async throws -> Res {
        let data = try await rawData(request)
        do {
            return try JSONDecoder().decode(Res.self, from: data)
        } catch {
            throw PulseTransportError.decoding("\(Res.self): \(error)")
        }
    }

    /// Adds auth, executes, and maps non-2xx into a `PulseError` (preferred) or
    /// `PulseTransportError`. Returns the raw 2xx body.
    private func rawData(_ request: URLRequest) async throws -> Data {
        var req = request
        guard let token = await tokenProvider(), !token.isEmpty else {
            throw PulseTransportError.notAuthenticated
        }
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            // A cancelled request (task superseded, or SwiftUI tore down the
            // owning Task) is benign — surface it as a real CancellationError so
            // callers can ignore it rather than show "-999 cancelled".
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            throw PulseTransportError.network(String(describing: error))
        }
        guard let http = response as? HTTPURLResponse else {
            throw PulseTransportError.badResponse(status: -1)
        }
        guard (200...299).contains(http.statusCode) else {
            if var pe = try? JSONDecoder().decode(PulseError.self, from: data) {
                pe.httpStatus = http.statusCode
                throw pe
            }
            throw PulseTransportError.badResponse(status: http.statusCode)
        }
        return data
    }
}
