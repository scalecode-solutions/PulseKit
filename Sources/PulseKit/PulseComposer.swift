import SwiftUI
import PhotosUI
import UIKit

/// A photo selected for the draft: the preview image plus the JPEG bytes +
/// dimensions used for upload.
private struct PickedImage: Identifiable {
    let id = UUID()
    let image: UIImage
    let data: Data
    var width: Int { Int(image.size.width) }
    var height: Int { Int(image.size.height) }
}

/// The composer's single modal slot. One `.sheet(item:)` drives all of them —
/// stacking multiple `.sheet` modifiers on one view is a SwiftUI footgun that
/// breaks reliable content re-evaluation.
private enum ComposerSheet: String, Identifiable {
    case settings, video, audio, file
    var id: String { rawValue }
}

/// Pinned composer — collapsed slim row that expands INLINE into the full
/// composer (text · photos · emoji · expiry · send), in place, no modal sheet.
/// Mirrors the host app's PulseHubComposerBar. Lives in the feed's safeAreaInset so it
/// stays pinned above the scrolling feed.
struct PulseComposerBar: View {
    let me: PulseAuthor?
    let transport: any PulseTransport
    let onPost: (CreatePulseBody) -> Void

    @State private var isExpanded = false
    @State private var text = ""
    @State private var emoji = ""
    @State private var expirySeconds: Int?
    @State private var showEmojiStrip = false
    @State private var posting = false
    @State private var showPhotoPicker = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var photos: [PickedImage] = []
    @State private var audience: [UUID] = []
    @State private var contactsStore: PulseContactsStore
    @State private var activeSheet: ComposerSheet?
    @FocusState private var textFocused: Bool

    init(me: PulseAuthor?, transport: any PulseTransport,
         onPost: @escaping (CreatePulseBody) -> Void) {
        self.me = me
        self.transport = transport
        self.onPost = onPost
        _contactsStore = State(initialValue: PulseContactsStore(transport: transport))
    }

    private static let quickEmojis = ["😀","😂","❤️","🔥","🎉","👍","😮","😢","🚀","☕️","💪","🙏"]

    static let expiryOptions: [(label: String, seconds: Int?)] = [
        ("Never", nil), ("30 minutes", 1800), ("1 hour", 3600), ("3 hours", 10800),
        ("6 hours", 21600), ("12 hours", 43200), ("24 hours", 86400),
        ("3 days", 259200), ("7 days", 604800),
    ]

    private var canSend: Bool {
        !posting && (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                     || !photos.isEmpty || !emoji.isEmpty)
    }

    var body: some View {
        Group {
            if isExpanded { expanded } else { collapsed }
        }
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: isExpanded)
        .photosPicker(isPresented: $showPhotoPicker, selection: $pickerItems,
                      maxSelectionCount: 4, matching: .images)
        .onChange(of: pickerItems) { _, items in Task { await load(items) } }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .settings:
                PulsePostSettingsSheet(audience: $audience, expirySeconds: $expirySeconds,
                                       contactsStore: contactsStore)
            case .video: PulseVideoComposer(transport: transport, onPost: handleKindPost)
            case .file:  PulseFileComposer(transport: transport, onPost: handleKindPost)
            case .audio: PulseAudioComposer(transport: transport, onPost: handleKindPost)
            }
        }
    }

    // MARK: - Collapsed row

    private var collapsed: some View {
        HStack(spacing: 12) {
            Button { expand() } label: { PulseAvatar(author: me, size: 34) }
                .buttonStyle(.plain)
            Button { expand() } label: {
                Text("Whatcha doin'?")
                    .font(.system(size: 15)).italic()
                    .foregroundStyle(.secondary.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button { expand(); showPhotoPicker = true } label: {
                Image(systemName: "photo").font(.system(size: 18))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    // MARK: - Expanded composer

    private var expanded: some View {
        VStack(spacing: 12) {
            header
            if !photos.isEmpty { photoStrip }
            textHero
            actionBar
            if showEmojiStrip { emojiStrip }
            kindPills
        }
        .padding(14)
    }

    private var kindPills: some View {
        HStack(spacing: 10) {
            kindPill(.video, "video", "Video")
            kindPill(.audio, "mic", "Audio")
            kindPill(.file, "doc", "File")
            Spacer()
        }
    }

    private func kindPill(_ sheet: ComposerSheet, _ icon: String, _ label: String) -> some View {
        Button { activeSheet = sheet } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                Text(label)
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(.secondary.opacity(0.12), in: .capsule)
        }
        .buttonStyle(.plain)
    }

    private func handleKindPost(_ body: CreatePulseBody) {
        onPost(body)
        collapse()
        clearDraft()
    }

    private var header: some View {
        HStack(spacing: 10) {
            PulseAvatar(author: me, size: 34)
            Text("New pulse").font(.system(size: 15, weight: .semibold))
            Spacer()
            Button { collapse() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(.secondary.opacity(0.12)))
            }
            .frame(width: 44, height: 44).contentShape(Rectangle()).buttonStyle(.plain)
        }
    }

    private var photoStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(photos) { p in
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: p.image)
                            .resizable().scaledToFill()
                            .frame(width: 72, height: 72)
                            .clipShape(.rect(cornerRadius: 10))
                        Button {
                            photos.removeAll { $0.id == p.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .black.opacity(0.55))
                                .font(.system(size: 18))
                        }
                        .buttonStyle(.plain).padding(4)
                    }
                }
            }
        }
        .frame(height: 72)
    }

    private var textHero: some View {
        TextField("Whatcha doin'?", text: $text, axis: .vertical)
            .font(.system(size: 16))
            .focused($textFocused)
            .lineLimit(1...8)
            .padding(12)
            .background(.quaternary, in: .rect(cornerRadius: 12))
            .overlay(alignment: .bottomTrailing) {
                if !text.isEmpty {
                    Text("\(text.count)/2000")
                        .font(.caption2)
                        .foregroundStyle(text.count >= 2000 ? .red : .secondary)
                        .padding(8)
                        .allowsHitTesting(false)
                }
            }
            .onChange(of: text) { _, new in
                if new.count > 2000 { text = String(new.prefix(2000)) }
            }
    }

    private var actionBar: some View {
        HStack(spacing: 6) {
            Button {
                showEmojiStrip.toggle()
                if showEmojiStrip { textFocused = false }
            } label: {
                if emoji.isEmpty {
                    Image(systemName: "face.smiling").font(.system(size: 22))
                        .foregroundStyle(.secondary)
                } else {
                    Text(emoji).font(.system(size: 24))
                }
            }
            .frame(width: 44, height: 44).contentShape(.rect).buttonStyle(.plain)

            Button { showPhotoPicker = true } label: {
                Image(systemName: photos.isEmpty ? "photo" : "photo.fill.on.rectangle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(photos.isEmpty ? Color.secondary : Color.accentColor)
            }
            .frame(width: 44, height: 44).contentShape(.rect).buttonStyle(.plain)

            Spacer()

            Button {
                contactsStore.loadIfNeeded()
                activeSheet = .settings
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: settingsIcon)
                        .font(.system(size: 14, weight: .medium))
                    if let label = expiryShortLabel {
                        Text(label).font(.system(size: 12, weight: .semibold))
                    }
                }
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(Color.accentColor.opacity(0.14), in: .capsule)
            }
            .buttonStyle(.plain)

            Button(action: submit) {
                if posting {
                    ProgressView().frame(width: 30, height: 30)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(canSend ? Color.accentColor : Color.secondary.opacity(0.3))
                }
            }
            .frame(width: 44, height: 44).contentShape(.rect)
            .disabled(!canSend).buttonStyle(.plain)
        }
    }

    private var emojiStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Self.quickEmojis, id: \.self) { e in
                    Button {
                        emoji = (emoji == e) ? "" : e
                        showEmojiStrip = false
                    } label: {
                        Text(e).font(.system(size: 28))
                            .opacity(emoji.isEmpty || emoji == e ? 1 : 0.4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
        }
        .frame(height: 44)
    }

    private var settingsIcon: String {
        if !audience.isEmpty { return "person.2.fill" }
        return expirySeconds == nil ? "slider.horizontal.3" : "hourglass"
    }

    private var expiryShortLabel: String? {
        guard let s = expirySeconds else { return nil }
        switch s {
        case 1800: return "30m"; case 3600: return "1h"; case 10800: return "3h"
        case 21600: return "6h"; case 43200: return "12h"; case 86400: return "24h"
        case 259200: return "3d"; case 604800: return "7d"; default: return "\(s / 3600)h"
        }
    }

    // MARK: - State transitions

    private func expand() {
        isExpanded = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { textFocused = true }
        contactsStore.loadIfNeeded()   // preload so the picker is ready when opened
    }

    private func collapse() {
        textFocused = false
        showEmojiStrip = false
        isExpanded = false
    }

    private func clearDraft() {
        text = ""; emoji = ""; expirySeconds = nil
        photos = []; pickerItems = []
        audience = []
    }

    // MARK: - Actions

    /// First http(s) link in the text — a text-only pulse containing a link is
    /// posted as kind=url so the server fetches a preview (the host app does this via a
    /// separate share flow; inline detection is friendlier for the lab).
    private static func firstURL(in text: String) -> String? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        for m in detector.matches(in: text, range: range) {
            if let url = m.url, let scheme = url.scheme, scheme.hasPrefix("http") {
                return url.absoluteString
            }
        }
        return nil
    }

    private func load(_ items: [PhotosPickerItem]) async {
        var loaded: [PickedImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let ui = UIImage(data: data),
               let jpeg = ui.jpegData(compressionQuality: 0.85) {
                loaded.append(PickedImage(image: ui, data: jpeg))
            }
        }
        photos = loaded
    }

    private func submit() {
        guard canSend else { return }
        posting = true
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let moodEmoji = emoji.isEmpty ? nil : emoji
        let expiry = expirySeconds
        let aud = audience
        let uploads = photos.map { ($0.data, $0.width, $0.height) }

        Task {
            var refs: [MediaRef] = []
            for (data, w, h) in uploads {
                if let dto = try? await transport.uploadFile(data, mimeType: "image/jpeg") {
                    refs.append(MediaRef(type: "image", ref: dto.id.uuidString,
                                         url: dto.url, width: w, height: h))
                }
            }
            var kind = refs.count > 1 ? "gallery" : (refs.isEmpty ? "text" : "image")
            var linkURL: String?
            if refs.isEmpty, let link = Self.firstURL(in: trimmed) {
                kind = "url"          // server fetches the preview for url-kind
                linkURL = link
            }
            let body = CreatePulseBody(
                text: trimmed, kind: kind, emoji: moodEmoji,
                files: refs.isEmpty ? nil : refs, url: linkURL, expiresIn: expiry,
                audience: aud.isEmpty ? nil : aud
            )
            await MainActor.run {
                onPost(body)
                posting = false
                clearDraft()
                collapse()
            }
        }
    }
}
