import SwiftUI
import AVKit
import AVFoundation
import QuickLook

/// Formats a media duration (seconds) as m:ss.
func pulseDurationLabel(_ seconds: Double) -> String {
    let s = Int(seconds.rounded())
    return String(format: "%d:%02d", s / 60, s % 60)
}

// MARK: - Video

/// Poster cell with a play affordance; tap downloads the authed blob and plays
/// it fullscreen (AVPlayer needs a local file for our token-gated blobs).
struct PulseVideoCell: View {
    let media: MediaRef
    @State private var playerURL: URL?
    @State private var showPlayer = false
    @State private var loading = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.black.opacity(0.85))
            VStack(spacing: 6) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 48)).foregroundStyle(.white.opacity(0.92))
                if let d = media.duration {
                    Text(pulseDurationLabel(d)).font(.caption).foregroundStyle(.white.opacity(0.75))
                }
            }
            if loading { ProgressView().tint(.white) }
        }
        .frame(height: 200).frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { play() }
        .fullScreenCover(isPresented: $showPlayer) {
            if let url = playerURL { PulseVideoPlayerView(url: url) }
        }
    }

    private func play() {
        if playerURL != nil { showPlayer = true; return }
        loading = true
        Task {
            let url = await PulseMediaBox.downloadToFile(media)
            loading = false
            playerURL = url
            if url != nil { showPlayer = true }
        }
    }
}

struct PulseVideoPlayerView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            VideoPlayer(player: AVPlayer(url: url)).ignoresSafeArea()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28)).foregroundStyle(.white.opacity(0.9)).padding()
            }
        }
    }
}

// MARK: - Audio

/// Inline audio player — play/pause + duration. Downloads the authed blob on
/// first play.
struct PulseAudioCell: View {
    let media: MediaRef
    @State private var player: AVAudioPlayer?
    @State private var playing = false
    @State private var loading = false

    var body: some View {
        HStack(spacing: 12) {
            Button { toggle() } label: {
                Image(systemName: loading ? "hourglass"
                      : (playing ? "pause.circle.fill" : "play.circle.fill"))
                    .font(.system(size: 36)).foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain).disabled(loading)

            Image(systemName: "waveform").font(.system(size: 18)).foregroundStyle(.secondary)
            if let d = media.duration {
                Text(pulseDurationLabel(d)).font(.system(size: 13)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(.secondary.opacity(0.1), in: .rect(cornerRadius: 12))
    }

    private func toggle() {
        if let p = player {
            if playing { p.pause() } else {
                if p.currentTime >= p.duration { p.currentTime = 0 }
                p.play()
            }
            playing.toggle()
            return
        }
        loading = true
        Task {
            guard let url = await PulseMediaBox.downloadToFile(media) else { loading = false; return }
            loading = false
            try? AVAudioSession.sharedInstance().setCategory(.playback)
            try? AVAudioSession.sharedInstance().setActive(true)
            player = try? AVAudioPlayer(contentsOf: url)
            player?.play()
            playing = player != nil
        }
    }
}

// MARK: - File

/// File chip — name + open affordance; tap downloads the authed blob and shows
/// it in QuickLook.
struct PulseFileCell: View {
    let media: MediaRef
    @State private var fileURL: URL?
    @State private var loading = false

    var body: some View {
        Button { open() } label: {
            HStack(spacing: 12) {
                Image(systemName: "doc.fill").font(.system(size: 28)).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(media.name ?? "File")
                        .font(.system(size: 15, weight: .medium)).foregroundStyle(.primary).lineLimit(1)
                    Text("Tap to open").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if loading { ProgressView() }
                else { Image(systemName: "arrow.down.circle").foregroundStyle(.secondary) }
            }
            .padding(12)
            .background(.secondary.opacity(0.1), in: .rect(cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .quickLookPreview($fileURL)
    }

    private func open() {
        guard !loading else { return }
        loading = true
        Task {
            let url = await PulseMediaBox.downloadToFile(media)
            loading = false
            fileURL = url
        }
    }
}
