import SwiftUI

/// URL-kind body — a rich link-preview card when the server fetched one, else a
/// compact link chip. Ported from the host app's urlBody / ServerLinkPreviewCard.
struct PulseLinkBlock: View {
    let pulse: PulseEntity

    var body: some View {
        if let preview = pulse.linkPreview {
            LinkPreviewCard(preview: preview)
        } else if let s = pulse.url, let url = URL(string: s) {
            linkChip(url)
        }
    }

    private func linkChip(_ url: URL) -> some View {
        Link(destination: url) {
            HStack(spacing: 8) {
                Image(systemName: "link")
                    .font(.system(size: 16)).foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .background(.secondary.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(url.host ?? url.absoluteString).font(.subheadline).fontWeight(.semibold).lineLimit(1)
                    Text(url.absoluteString).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
            .padding(8)
            .background(.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct LinkPreviewCard: View {
    let preview: LinkPreview

    var body: some View {
        Link(destination: URL(string: preview.url) ?? URL(string: "https://invalid")!) {
            VStack(alignment: .leading, spacing: 0) {
                if let img = preview.imageUrl, let u = URL(string: img) {
                    AsyncImage(url: u) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Rectangle().fill(.secondary.opacity(0.12))
                    }
                    .frame(height: 160)
                    .frame(maxWidth: .infinity)
                    .clipped()
                }
                VStack(alignment: .leading, spacing: 3) {
                    if let site = preview.siteName {
                        Text(site.uppercased()).font(.caption2).foregroundStyle(.secondary).tracking(0.5)
                    }
                    if let title = preview.title {
                        Text(title).font(.subheadline).fontWeight(.semibold).lineLimit(2)
                    }
                    if let desc = preview.description {
                        Text(desc).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
            }
            .background(.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
