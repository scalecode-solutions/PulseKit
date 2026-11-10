import SwiftUI
import UIKit

/// Global media context for resolving + authenticating blob image loads.
/// Configured by PulseFeedView / PulseDetailView from the PulseConfig — mirrors
/// PulseAuthorBox. mvPulse's blob endpoint (`/v0/pulse/files/{id}/blob`) requires
/// a Bearer token and stores a HOST-LESS relative url in the head, so a plain
/// AsyncImage can neither resolve nor authenticate it. This box does both.
@MainActor
enum PulseMediaBox {
    private static var baseURL: URL?
    private static var tokenProvider: (@Sendable () async -> String?)?
    private static let cache = NSCache<NSURL, UIImage>()

    static func configure(baseURL: URL, tokenProvider: @escaping @Sendable () async -> String?) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
    }

    /// Resolve a MediaRef to (absolute URL, needsAuth). External http(s) URLs load
    /// directly; our blob paths / file-id refs resolve against the base URL and
    /// carry the token.
    static func resolve(_ m: MediaRef) -> (url: URL, needsAuth: Bool)? {
        // Absolute http(s) URL.
        if let s = m.url, let u = URL(string: s), let scheme = u.scheme,
           scheme.hasPrefix("http"), u.host != nil {
            return (u, u.host == baseURL?.host)   // ours → auth; external → no auth
        }
        // Relative blob path (e.g. "/v0/pulse/files/<id>/blob").
        if let s = m.url, !s.isEmpty, let base = baseURL,
           let u = URL(string: s, relativeTo: base)?.absoluteURL {
            return (u, true)
        }
        // Bare file-id ref → build the blob URL.
        if let base = baseURL, let id = UUID(uuidString: m.ref) {
            return (base.appendingPathComponent("v0/pulse/files/\(id.uuidString)/blob"), true)
        }
        return nil
    }

    static func cached(_ url: URL) -> UIImage? { cache.object(forKey: url as NSURL) }
    static func store(_ img: UIImage, for url: URL) { cache.setObject(img, forKey: url as NSURL) }
    static func token() async -> String? { await tokenProvider?() }

    // --- blob download (video / audio / file): AVPlayer / AVAudioPlayer /
    // QuickLook need a local file URL, so download the authed blob to a temp
    // file (cached by source URL) with a type-appropriate extension.

    private static var fileCache: [URL: URL] = [:]

    static func downloadToFile(_ media: MediaRef) async -> URL? {
        guard let (url, needsAuth) = resolve(media) else { return nil }
        if let cached = fileCache[url], FileManager.default.fileExists(atPath: cached.path) { return cached }
        var req = URLRequest(url: url)
        if needsAuth, let token = await token(), !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (tmp, resp) = try await URLSession.shared.download(for: req)
            if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) { return nil }
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(fileExtension(for: media))
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tmp, to: dest)
            fileCache[url] = dest
            return dest
        } catch {
            return nil
        }
    }

    private static let mimeExt: [String: String] = [
        "video/mp4": "mp4", "video/quicktime": "mov", "audio/mpeg": "mp3",
        "audio/mp4": "m4a", "audio/m4a": "m4a", "audio/x-m4a": "m4a", "application/pdf": "pdf",
    ]

    private static func fileExtension(for m: MediaRef) -> String {
        if let name = m.name, let dot = name.lastIndex(of: "."), dot < name.index(before: name.endIndex) {
            return String(name[name.index(after: dot)...])
        }
        if let mime = m.mimeType {
            if let ext = mimeExt[mime] { return ext }
            if let slash = mime.lastIndex(of: "/") { return String(mime[mime.index(after: slash)...]) }
        }
        switch m.type {
        case "video": return "mp4"
        case "audio": return "m4a"
        default: return "dat"
        }
    }
}

/// Loads (and authenticates) a pulse MediaRef into an Image. Replaces AsyncImage
/// for blob-backed media, which can't send the auth header. `placeholder` is
/// handed `failed` so callers can distinguish loading from a hard failure.
struct PulseAuthedImage<Content: View, Placeholder: View>: View {
    let media: MediaRef
    @ViewBuilder var content: (Image) -> Content
    @ViewBuilder var placeholder: (_ failed: Bool) -> Placeholder

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let img = image ?? cachedImage { content(Image(uiImage: img)) }
            else { placeholder(failed) }
        }
        .task(id: media.ref + (media.url ?? "")) { await load() }
    }

    /// A synchronous in-memory cache hit, so a cached image renders on the very
    /// first body eval — before `.task` runs. Needed for context-menu preview
    /// snapshots (which capture before async load finishes) and gives instant
    /// display on scroll-back.
    private var cachedImage: UIImage? {
        guard let (url, _) = PulseMediaBox.resolve(media) else { return nil }
        return PulseMediaBox.cached(url)
    }

    private func load() async {
        image = nil
        failed = false
        guard let (url, needsAuth) = PulseMediaBox.resolve(media) else { failed = true; return }
        if let hit = PulseMediaBox.cached(url) { image = hit; return }

        var req = URLRequest(url: url)
        if needsAuth, let token = await PulseMediaBox.token(), !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                failed = true; return
            }
            guard let ui = UIImage(data: data) else { failed = true; return }
            PulseMediaBox.store(ui, for: url)
            image = ui
        } catch is CancellationError {
            // benign — view went away or task superseded
        } catch {
            failed = true
        }
    }
}
