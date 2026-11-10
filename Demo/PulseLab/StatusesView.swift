import SwiftUI
import UIKit
import PulseKit

/// Rehearsal of the host app's `ConversationCardV2` pulse line, standalone: a list of
/// rows (one per user id), each reading its latest pulse from **one shared**
/// `PulseStatusStore` that was refreshed in a single batch. This is exactly how
/// The host app will wire it — `store.refresh(for: visibleIds)` once, each card reads
/// `store.latest(for: id)` reactively. The host owns avatar rendering (here a
/// simple inline avatar; the host app uses its `ProfileImageView`).
struct StatusesView: View {
    let transport: any PulseTransport

    @State private var store: PulseStatusStore
    @State private var people: [PulseContact] = []
    @Environment(\.dismiss) private var dismiss

    init(transport: any PulseTransport) {
        self.transport = transport
        _store = State(initialValue: PulseStatusStore(transport: transport))
    }

    var body: some View {
        NavigationStack {
            List(people) { person in
                StatusRow(contact: person, pulse: store.latest(for: person.id))
            }
            .overlay { if people.isEmpty { ProgressView() } }
            .navigationTitle("Statuses")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await load() }
            .refreshable { await store.refresh(for: people.map(\.id)) }
        }
    }

    /// me + contacts = the "cards"; one batch refresh covers them all.
    private func load() async {
        var list: [PulseContact] = []
        if let mine = try? await transport.me() { list.append(mine) }
        if let contacts = try? await transport.contacts() { list.append(contentsOf: contacts) }
        people = list
        await store.refresh(for: list.map(\.id))
    }
}

private struct StatusRow: View {
    let contact: PulseContact
    let pulse: PulseDTO?

    var body: some View {
        HStack(spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName).font(.system(size: 15, weight: .semibold))
                if let pulse {
                    Text("⚡ \(pulse.statusPreview)")
                        .font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                } else {
                    Text("no pulse").font(.system(size: 13)).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if let pulse {
                Text(relative(pulse.createdAt)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var displayName: String {
        contact.name.isEmpty ? "Member \(contact.id.uuidString.prefix(8))" : contact.name
    }

    @ViewBuilder private var avatar: some View {
        if let b64 = contact.avatar, let data = Data(base64Encoded: b64), let img = UIImage(data: data) {
            Image(uiImage: img).resizable().scaledToFill()
                .frame(width: 40, height: 40).clipShape(Circle())
        } else {
            Circle().fill(.tint.opacity(0.18)).frame(width: 40, height: 40)
                .overlay(Text(initials).font(.system(size: 15, weight: .semibold)).foregroundStyle(.tint))
        }
    }

    private var initials: String {
        contact.name.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased()
    }

    private func relative(_ ms: Int64) -> String {
        let date = Date(timeIntervalSince1970: Double(ms) / 1000)
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
}
