import SwiftUI
import UIKit
import PulseKit

/// PulseLab's host-injected avatar — deliberately a SQUIRCLE with a ring (not
/// PulseKit's plain circle) so the avatar-view injection is *unmistakable* in the
/// feed. It decodes the same `avatarRef` base64 the built-in path would, just in a
/// different shape. The host app injects its `ProfileImageView` here instead.
struct SquircleAvatar: View {
    let author: PulseAuthor
    let size: CGFloat

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
    }

    var body: some View {
        Group {
            if let b64 = author.avatarRef,
               let data = Data(base64Encoded: b64),
               let img = UIImage(data: data) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                shape.fill(.tint.opacity(0.2))
                    .overlay(
                        Text(initials)
                            .font(.system(size: size * 0.4, weight: .bold))
                            .foregroundStyle(.tint)
                    )
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.stroke(.tint.opacity(0.6), lineWidth: 1.5)) // ring → obvious injection
    }

    private var initials: String {
        author.displayName.split(separator: " ").prefix(2)
            .compactMap { $0.first }.map(String.init).joined().uppercased()
    }
}
