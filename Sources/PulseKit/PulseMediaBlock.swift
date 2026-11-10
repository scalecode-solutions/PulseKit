import SwiftUI

/// Media renderer for a pulse — single image (aspect-clamped) or a 2/3/4+ grid,
/// with tap-to-fullscreen. Reimplemented from the host app's PulseHubImageBlock using
/// `AsyncImage` (no Nuke / chat infra). Non-image kinds (video/audio/file) get a
/// simple typed placeholder for now.
struct PulseMediaBlock: View {
    let pulse: PulseEntity
    @State private var fullscreenIndex: Int?

    private var mediaItems: [MediaRef] {
        if !pulse.files.isEmpty { return pulse.files }
        if let m = pulse.mediaUrl, !m.isEmpty { return [MediaRef(type: "image", ref: m, url: m)] }
        return []
    }

    var body: some View {
        if mediaItems.isEmpty {
            EmptyView()
        } else {
            switch pulse.kind {
            case "video": PulseVideoCell(media: mediaItems[0])
            case "audio": PulseAudioCell(media: mediaItems[0])
            case "file":
                VStack(spacing: 8) {
                    ForEach(Array(mediaItems.enumerated()), id: \.offset) { _, m in
                        PulseFileCell(media: m)
                    }
                }
            default:
                imageContent
            }
        }
    }

    private var imageContent: some View {
        Group {
            if mediaItems.count == 1 { singleImage(mediaItems[0]) } else { grid }
        }
        .fullscreenMedia(index: $fullscreenIndex, items: mediaItems)
    }

    /// Single image, framed like the host app's PulseHubSingleImage. A clear rectangle
    /// sized by the image's aspect — clamped to [1/1.4, 2.0] so a super-tall
    /// portrait or wide panorama can't blow the card up to full-screen — with the
    /// image as an overlay. In-bounds: scaledToFill (exact, no crop). Out-of-bounds
    /// (extreme): scaledToFit over a blurred fill, so the whole image is visible
    /// with no letterbox bars.
    @ViewBuilder
    private func singleImage(_ m: MediaRef) -> some View {
        let natural: CGFloat? = {
            if let w = m.width, let h = m.height, w > 0, h > 0 { return CGFloat(w) / CGFloat(h) }
            return nil
        }()
        let minRatio: CGFloat = 1.0 / 1.4
        let maxRatio: CGFloat = 2.0
        let displayRatio = natural.map { min(max($0, minRatio), maxRatio) } ?? 1.0
        let isExtreme = natural.map { $0 < minRatio || $0 > maxRatio } ?? false

        Rectangle()
            .fill(Color.clear)
            .aspectRatio(displayRatio, contentMode: .fit)
            .overlay(
                PulseAuthedImage(media: m) { img in
                    if isExtreme {
                        ZStack {
                            img.resizable().scaledToFill().blur(radius: 18)
                            img.resizable().scaledToFit()
                        }
                    } else {
                        img.resizable().scaledToFill()
                    }
                } placeholder: { failed in
                    placeholder.overlay(
                        failed
                            ? AnyView(Image(systemName: "photo").foregroundStyle(.secondary))
                            : AnyView(ProgressView())
                    )
                }
                .clipped()
            )
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture { fullscreenIndex = 0 }
    }

    @ViewBuilder
    private func imageCell(_ m: MediaRef, index: Int, height: CGFloat? = nil) -> some View {
        let ratio: CGFloat = {
            if let w = m.width, let h = m.height, w > 0, h > 0 {
                return min(max(CGFloat(w) / CGFloat(h), 1.0 / 1.4), 2.0)
            }
            return 1.4
        }()
        PulseAuthedImage(media: m) { img in
            img.resizable().scaledToFill()
        } placeholder: { failed in
            placeholder.overlay(
                failed
                    ? AnyView(Image(systemName: "photo").foregroundStyle(.secondary))
                    : AnyView(ProgressView())
            )
        }
        .aspectRatio(height == nil ? ratio : nil, contentMode: .fill)
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { fullscreenIndex = index }
    }

    private var grid: some View {
        let items = Array(mediaItems.prefix(4))
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4)], spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, m in
                imageCell(m, index: i, height: 120)
                    .overlay(alignment: .bottomTrailing) {
                        if i == 3 && mediaItems.count > 4 {
                            Text("+\(mediaItems.count - 4)")
                                .font(.headline).foregroundStyle(.white)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(.black.opacity(0.45))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
            }
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.secondary.opacity(0.12))
    }
}

struct IdxBox: Identifiable { let i: Int; var id: Int { i } }

extension View {
    /// Fullscreen media presentation.
    func fullscreenMedia(index: Binding<Int?>, items: [MediaRef]) -> some View {
        self.fullScreenCover(item: Binding(
            get: { index.wrappedValue.map { IdxBox(i: $0) } },
            set: { index.wrappedValue = $0?.i }
        )) { box in
            PulseFullscreenMedia(items: items, start: box.i) { index.wrappedValue = nil }
        }
    }
}

/// Simple zoomable fullscreen pager for media (uses `.page` style).
struct PulseFullscreenMedia: View {
    let items: [MediaRef]
    let start: Int
    let onClose: () -> Void
    @State private var index: Int

    init(items: [MediaRef], start: Int, onClose: @escaping () -> Void) {
        self.items = items; self.start = start; self.onClose = onClose
        _index = State(initialValue: start)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, m in
                    PulseAuthedImage(media: m) { img in
                        img.resizable().scaledToFit()
                    } placeholder: { _ in
                        ProgressView().tint(.white)
                    }
                    .tag(i)
                }
            }
            .tabViewStyle(.page)
            Button { onClose() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28)).foregroundStyle(.white.opacity(0.9))
                    .padding()
            }
        }
    }
}
