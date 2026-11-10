import SwiftUI
import PulseKit
import MvAuth

struct ContentView: View {
    @State private var auth = AuthModel()
    @State private var showStatuses = false

    var body: some View {
        switch auth.state {
        case .loggedIn(let profile):
            feed(for: profile)
        default:
            LoginView(auth: auth)
        }
    }

    private func feed(for profile: UserProfile) -> some View {
        let tokenProvider: @Sendable () async -> String? = { [auth] in await auth.accessToken() }
        let transport = HTTPPulseTransport(baseURL: auth.server.pulseBaseURL, tokenProvider: tokenProvider)
        let config = PulseConfig(
            baseURL: auth.server.pulseBaseURL,
            currentUserID: UUID(uuidString: profile.userID) ?? UUID(),
            tokenProvider: tokenProvider,
            authorResolver: LabRoster(
                myID: profile.userID,
                myName: profile.displayName ?? profile.handle ?? "You",
                transport: transport
            )
        )
        return NavigationStack {
            PulseFeedView(
                config: config,
                store: PulseStore(inMemory: true),
                transport: config.transport,
                embedded: true,
                // Host-injected avatar — proves the seam the host app will use
                // (it'll pass ProfileImageView here). The squircle makes the
                // injection unmistakable vs PulseKit's built-in circle.
                avatarView: { author, size in AnyView(SquircleAvatar(author: author, size: size)) }
            )
            // Header is host chrome — the host app owns it on integration. The lab just
            // leaves the nav-bar slot for it; PulseKit owns the pinned composer.
            .navigationTitle("Pulse")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Statuses") { showStatuses = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sign Out", role: .destructive) { auth.logOut() }
                }
            }
            .sheet(isPresented: $showStatuses) {
                StatusesView(transport: transport)
            }
        }
    }
}

#Preview {
    ContentView()
        .tint(.tardisBlue)
}
