import SwiftUI

// YouTube detection + a dedicated 16:9 video card. Ported from the host app's
// Pulse.youtubeMatch + PulseHubYouTubeBlock. Tap routes to the YouTube app via
// universal links — never inline playback (privacy, parental controls, and the
// deliberate "leave to watch" friction that keeps the feed from going passive).

public enum YouTubeBrand: Sendable {
    case youtube, youtubeMusic
    public var displayName: String { self == .youtube ? "YouTube" : "YouTube Music" }
}

public struct YouTubeMatch: Equatable, Sendable {
    public let videoId: String
    public let brand: YouTubeBrand
    public var thumbnailURL: URL? { URL(string: "https://i.ytimg.com/vi/\(videoId)/hqdefault.jpg") }
}

public enum PulseYouTube {
    /// Pure URL → match? — watch / youtu.be / shorts / embed / live / v, plus the
    /// music subdomain. Video ids are exactly 11 URL-safe-base64 chars.
    public static func match(_ urlString: String) -> YouTubeMatch? {
        guard let parsed = URL(string: urlString), let rawHost = parsed.host?.lowercased() else { return nil }
        let brand: YouTubeBrand
        let host: String
        if rawHost == "music.youtube.com" {
            brand = .youtubeMusic; host = "youtube.com"
        } else {
            brand = .youtube; host = strip(rawHost)
        }
        let path = parsed.path
        switch host {
        case "youtu.be":
            let candidate = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let id = candidate.split(separator: "/").first.map(String.init) ?? candidate
            return isValidID(id) ? YouTubeMatch(videoId: id, brand: brand) : nil
        case "youtube.com":
            if path == "/watch" || path == "/watch/" {
                let id = URLComponents(url: parsed, resolvingAgainstBaseURL: false)?
                    .queryItems?.first { $0.name == "v" }?.value ?? ""
                return isValidID(id) ? YouTubeMatch(videoId: id, brand: brand) : nil
            }
            for prefix in ["/shorts/", "/embed/", "/live/", "/v/"] where path.hasPrefix(prefix) {
                let rem = String(path.dropFirst(prefix.count))
                let id = rem.split(separator: "/").first.map(String.init) ?? rem
                return isValidID(id) ? YouTubeMatch(videoId: id, brand: brand) : nil
            }
            return nil
        default:
            return nil
        }
    }

    private static func strip(_ host: String) -> String {
        if host.hasPrefix("www.") { return String(host.dropFirst(4)) }
        if host.hasPrefix("m.") { return String(host.dropFirst(2)) }
        return host
    }

    public static func isValidID(_ id: String) -> Bool {
        id.count == 11 && id.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }
}

public extension PulseEntity {
    var youtubeMatch: YouTubeMatch? { url.flatMap(PulseYouTube.match) }
}

/// The 16:9 video card — thumbnail + centered play button + brand chip.
struct PulseYouTubeBlock: View {
    let pulse: PulseEntity
    private let youtubeRed = Color(red: 1, green: 0, blue: 0)

    var body: some View {
        if let match = pulse.youtubeMatch, let s = pulse.url, let url = URL(string: s) {
            Link(destination: url) {
                VStack(alignment: .leading, spacing: 8) {
                    thumbnail(match)
                    if let title = pulse.linkPreview?.title, !title.isEmpty {
                        Text(title).font(.system(size: 16, weight: .semibold))
                            .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func thumbnail(_ match: YouTubeMatch) -> some View {
        ZStack {
            Color.secondary.opacity(0.15).aspectRatio(16.0 / 9.0, contentMode: .fit).frame(maxWidth: .infinity)
            if let t = match.thumbnailURL {
                AsyncImage(url: t) { phase in
                    if case .success(let image) = phase { image.resizable().aspectRatio(contentMode: .fill) }
                }
                .aspectRatio(16.0 / 9.0, contentMode: .fit).frame(maxWidth: .infinity).clipped()
            }
            Image(systemName: "play.fill")
                .font(.system(size: 26, weight: .black)).foregroundStyle(.white)
                .frame(width: 68, height: 48)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(youtubeRed))
                .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
            VStack { Spacer(); HStack { Spacer(); brandChip(match.brand).padding(8) } }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func brandChip(_ brand: YouTubeBrand) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "play.rectangle.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(youtubeRed)
            Text(brand.displayName).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(.black.opacity(0.7)))
    }
}
