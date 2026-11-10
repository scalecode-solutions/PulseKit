import SwiftUI

/// A contact resolved for the audience picker — id + display name (resolved via
/// the author resolver, so the host app supplies real names).
struct AudienceContact: Identifiable, Hashable {
    let id: UUID
    let name: String
    let avatarRef: String?
}

/// Post-settings sheet: visibility (Everyone / Specific People + contact
/// multi-select) and disappear-after duration. Mirrors the host app's
/// PulseHubPostSettingsSheet. An empty audience = public.
struct PulsePostSettingsSheet: View {
    @Binding var audience: [UUID]
    @Binding var expirySeconds: Int?
    /// Observed (not snapshotted): a load that finishes after this sheet is on
    /// screen still re-renders the People list — no presentation race.
    let contactsStore: PulseContactsStore

    @Environment(\.dismiss) private var dismiss
    @State private var isPrivate: Bool

    init(audience: Binding<[UUID]>, expirySeconds: Binding<Int?>, contactsStore: PulseContactsStore) {
        _audience = audience
        _expirySeconds = expirySeconds
        self.contactsStore = contactsStore
        _isPrivate = State(initialValue: !audience.wrappedValue.isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Who can see this") {
                    Picker("Visibility", selection: $isPrivate) {
                        Text("Everyone").tag(false)
                        Text("Specific People").tag(true)
                    }
                    .pickerStyle(.segmented)
                }

                if isPrivate {
                    Section("People") { peopleContent }
                }

                Section("Disappear after") {
                    Picker("Duration", selection: $expirySeconds) {
                        ForEach(PulseComposerBar.expiryOptions, id: \.label) { opt in
                            Text(opt.label).tag(opt.seconds)
                        }
                    }
                }
            }
            .navigationTitle("Post settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: isPrivate) { _, priv in
                if !priv { audience = [] }
            }
        }
        .presentationDetents([.medium, .large])
        .task { contactsStore.loadIfNeeded() }
    }

    /// The People list, rendered honestly from the load state — loading, error
    /// (with retry), empty, or the contacts — so a failed fetch never silently
    /// looks like "no contacts."
    @ViewBuilder
    private var peopleContent: some View {
        switch contactsStore.state {
        case .idle, .loading:
            HStack(spacing: 8) {
                ProgressView()
                Text("Loading contacts…").foregroundStyle(.secondary)
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Text(message).font(.footnote).foregroundStyle(.red)
                Button("Retry") { contactsStore.reload() }
            }
        case .loaded(let contacts):
            if contacts.isEmpty {
                Text("No contacts to choose from yet.").foregroundStyle(.secondary)
            } else {
                ForEach(contacts) { c in
                    Button { toggle(c.id) } label: {
                        HStack(spacing: 10) {
                            PulseAvatar(author: PulseAuthor(userID: c.id, displayName: c.name, avatarRef: c.avatarRef), size: 28)
                            Text(c.name).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: audience.contains(c.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(audience.contains(c.id) ? Color.accentColor : .secondary)
                        }
                    }
                }
                if audience.isEmpty {
                    Text("Pick at least one person.")
                        .font(.footnote).foregroundStyle(.red)
                }
            }
        }
    }

    private func toggle(_ id: UUID) {
        if let i = audience.firstIndex(of: id) { audience.remove(at: i) }
        else { audience.append(id) }
    }
}
