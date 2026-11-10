import SwiftUI
import PhotosUI
import AVKit
import AVFoundation
import UniformTypeIdentifiers

// Shared: upload a blob and assemble a single-media pulse body. Returns nil on
// upload failure. The caller (a @MainActor view) invokes onPost — keeps the
// closure off the nonisolated async boundary (Swift 6).
private func uploadMedia(
    transport: any PulseTransport,
    data: Data, mimeType: String, kind: String, type: String, caption: String,
    width: Int? = nil, height: Int? = nil, duration: Double? = nil, name: String? = nil
) async throws -> CreatePulseBody {
    let dto = try await transport.uploadFile(data, mimeType: mimeType)
    let ref = MediaRef(type: type, ref: dto.id.uuidString, url: dto.url,
                       width: width, height: height, name: name, mimeType: mimeType, duration: duration)
    return CreatePulseBody(
        text: caption.trimmingCharacters(in: .whitespacesAndNewlines),
        kind: kind, files: [ref]
    )
}

/// A human-readable upload/post failure message for the composer sheets.
private func pulseUploadFailure(_ error: Error) -> String {
    if let e = error as? PulseTransportError {
        switch e {
        case .notAuthenticated: return "You're signed out — sign in and try again."
        case .badResponse(let s): return "Upload failed (HTTP \(s))."
        case .decoding: return "Unexpected server response."
        case .network(let m): return "Network error: \(m)"
        }
    }
    if let e = error as? PulseError { return e.message }
    return "Couldn't post: \(error.localizedDescription)"
}

// MARK: - Video

struct PulseVideoComposer: View {
    let transport: any PulseTransport
    let onPost: (CreatePulseBody) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var item: PhotosPickerItem?
    @State private var localURL: URL?
    @State private var data: Data?
    @State private var duration: Double?
    @State private var dims: (Int, Int)?
    @State private var caption = ""
    @State private var posting = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let localURL {
                        VideoPlayer(player: AVPlayer(url: localURL)).frame(height: 200)
                    }
                    PhotosPicker(localURL == nil ? "Choose a video" : "Choose a different video",
                                 selection: $item, matching: .videos)
                }
                Section { TextField("Add a caption…", text: $caption, axis: .vertical) }
                if let error { Section { Text(error).font(.footnote).foregroundStyle(.red) } }
            }
            .navigationTitle("New video").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: post) { if posting { ProgressView() } else { Text("Post").bold() } }
                        .disabled(data == nil || posting)
                }
            }
            .onChange(of: item) { _, it in Task { await load(it) } }
        }
    }

    private func load(_ it: PhotosPickerItem?) async {
        guard let it, let d = try? await it.loadTransferable(type: Data.self) else { return }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
        try? d.write(to: tmp)
        let asset = AVURLAsset(url: tmp)
        let dur = try? await asset.load(.duration)
        var size: (Int, Int)?
        if let track = try? await asset.loadTracks(withMediaType: .video).first,
           let n = try? await track.load(.naturalSize) {
            size = (Int(abs(n.width)), Int(abs(n.height)))
        }
        data = d; localURL = tmp
        duration = dur.map { CMTimeGetSeconds($0) }
        dims = size
    }

    private func post() {
        guard let data else { return }
        posting = true; error = nil
        Task {
            do {
                let body = try await uploadMedia(transport: transport, data: data, mimeType: "video/mp4",
                                kind: "video", type: "video", caption: caption,
                                width: dims?.0, height: dims?.1, duration: duration)
                onPost(body); dismiss()
            } catch {
                self.error = pulseUploadFailure(error)
            }
            posting = false
        }
    }
}

// MARK: - File

struct PulseFileComposer: View {
    let transport: any PulseTransport
    let onPost: (CreatePulseBody) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var importing = false
    @State private var fileURL: URL?
    @State private var data: Data?
    @State private var caption = ""
    @State private var posting = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button { importing = true } label: {
                        Label(fileURL?.lastPathComponent ?? "Choose a file", systemImage: "doc.badge.plus")
                    }
                }
                Section { TextField("Add a caption…", text: $caption, axis: .vertical) }
                if let error { Section { Text(error).font(.footnote).foregroundStyle(.red) } }
            }
            .navigationTitle("New file").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: post) { if posting { ProgressView() } else { Text("Post").bold() } }
                        .disabled(data == nil || posting)
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.item]) { result in
                if case .success(let url) = result { load(url) }
            }
        }
    }

    private func load(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        data = try? Data(contentsOf: url)
        fileURL = url
    }

    private func post() {
        guard let data, let fileURL else { return }
        posting = true; error = nil
        let name = fileURL.lastPathComponent
        let mime = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        Task {
            do {
                let body = try await uploadMedia(transport: transport, data: data, mimeType: mime,
                                kind: "file", type: "file", caption: caption, name: name)
                onPost(body); dismiss()
            } catch {
                self.error = pulseUploadFailure(error)
            }
            posting = false
        }
    }
}

// MARK: - Audio

struct PulseAudioComposer: View {
    let transport: any PulseTransport
    let onPost: (CreatePulseBody) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var recorder: AVAudioRecorder?
    @State private var recordURL: URL?
    @State private var recording = false
    @State private var elapsed: Double = 0
    @State private var caption = ""
    @State private var posting = false
    @State private var denied = false
    @State private var error: String?
    private let timer = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Button { recording ? stop() : start() } label: {
                            Image(systemName: recording ? "stop.circle.fill" : "mic.circle.fill")
                                .font(.system(size: 44))
                                .foregroundStyle(recording ? .red : Color.accentColor)
                        }
                        .buttonStyle(.plain)
                        Text(pulseDurationLabel(elapsed)).font(.system(size: 17, weight: .medium).monospacedDigit())
                        Spacer()
                        if recordURL != nil && !recording { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                    }
                    if denied { Text("Microphone access denied — enable it in Settings.").font(.footnote).foregroundStyle(.red) }
                    if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                }
                Section { TextField("Add a caption…", text: $caption, axis: .vertical) }
            }
            .navigationTitle("New audio").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { cleanup(); dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: post) { if posting { ProgressView() } else { Text("Post").bold() } }
                        .disabled(recordURL == nil || recording || posting)
                }
            }
            .onReceive(timer) { _ in if recording, let r = recorder { elapsed = r.currentTime } }
        }
    }

    private func start() {
        AVAudioApplication.requestRecordPermission { granted in
            Task { @MainActor in
                guard granted else { denied = true; return }
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString).appendingPathExtension("m4a")
                try? AVAudioSession.sharedInstance().setCategory(.playAndRecord, options: [.defaultToSpeaker])
                try? AVAudioSession.sharedInstance().setActive(true)
                let settings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100,
                    AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
                ]
                do {
                    let rec = try AVAudioRecorder(url: url, settings: settings)
                    guard rec.record() else { error = "Couldn't start recording."; return }
                    recorder = rec; recordURL = url; recording = true; elapsed = 0; error = nil
                } catch {
                    self.error = "Recorder failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func stop() {
        elapsed = recorder?.currentTime ?? elapsed
        recorder?.stop()
        recording = false
    }

    private func cleanup() {
        recorder?.stop()
        if let u = recordURL { try? FileManager.default.removeItem(at: u) }
    }

    private func post() {
        guard let url = recordURL, let data = try? Data(contentsOf: url) else {
            error = "No recording to post."; return
        }
        posting = true; error = nil
        let dur = elapsed
        Task {
            do {
                let body = try await uploadMedia(transport: transport, data: data, mimeType: "audio/m4a",
                                kind: "audio", type: "audio", caption: caption, duration: dur)
                onPost(body); dismiss()
            } catch {
                self.error = pulseUploadFailure(error)
            }
            posting = false
        }
    }
}
