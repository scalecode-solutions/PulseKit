# PulseKit

The Pulse feed — an inverted social feed of posts from the people you're
connected to — as a self-contained, iOS-only Swift package: DTOs, a REST
transport, SwiftData persistence, pull-sync, and the embedded feed UI (cards,
inline composer, media, reactions, replies, audience picker, avatars).

PulseKit is a **client**. It talks to the [mvPulse](https://pulse.mvchat.app)
backend over HTTPS and authenticates with an mvServer JWT supplied by the host
app. It ships no networking of its own beyond `URLSession`, and has **zero
external dependencies** — system frameworks only.

## Requirements

- iOS 26+
- Swift 6 (strict concurrency; the package builds under complete checking, no
  `@unchecked` escape hatches)
- iOS-only: `swift build` / `swift test` on a macOS host won't compile (no UIKit
  there). Build and test against an **iOS simulator** via Xcode / `xcodebuild`.

## Installation

Swift Package Manager.

```swift
// Package.swift
dependencies: [
    .package(
        url: "https://github.com/scalecode-solutions/PulseKit.git",
        .upToNextMinor(from: "0.1.0")   // 0.x: pin to minor — minors may break
    ),
]
```

…or in Xcode: **File ▸ Add Package Dependencies…** → the URL above → *Up to
Next Minor*.

## Quick start

The host provides the seams via `PulseConfig` — where the API lives, who the
viewer is, how to get an auth token, and how to resolve author identity — then
embeds `PulseFeedView`.

```swift
import PulseKit

// 1. Identity resolver — the host maps a user id to a display name + avatar.
//    (the host app backs this with its own contact store; standalone, the
//    directory-synced name/avatar arrive via mvPulse's contacts endpoint.)
struct MyRoster: PulseAuthorResolving {
    func author(for userID: UUID) async -> PulseAuthor? {
        PulseAuthor(userID: userID, displayName: "…", avatarRef: nil)
    }
}

// 2. Config: base URL, the signed-in user, a token provider (mvServer JWT),
//    and the resolver.
let config = PulseConfig(
    baseURL: URL(string: "https://pulse.mvchat.app")!,
    currentUserID: currentUserID,
    tokenProvider: { await auth.accessToken() },   // @Sendable () async -> String?
    authorResolver: MyRoster()
)

// 3. Embed the feed.
PulseFeedView(
    config: config,
    store: PulseStore(inMemory: true),  // or a persistent SwiftData store
    transport: config.transport,
    embedded: true                      // host owns the nav chrome
)
```

That's the whole surface. The feed handles its own sync, composer, media, and
detail navigation internally.

## How it fits together

```
Host app (yours / PulseLab)
  │  PulseConfig: baseURL · currentUserID · tokenProvider · authorResolver
  ▼
PulseKit  ──HTTPS + Bearer JWT──▶  mvPulse  (the pulse backend)
                                      ▲
                                      │ social graph (people directory + edges)
                                   mvServer  (auth + identity source)
```

- **`tokenProvider`** returns the current mvServer access token; PulseKit
  attaches it as `Bearer` on every request. The host owns login/refresh.
- **`authorResolver`** is the identity seam. Standalone, the synced people
  directory (name + base64 avatar) is served by mvPulse; in a host app, plug in
  the host app's own contact store for fresher names/photos.

Concurrency model: a **main-actor store + main `ModelContext`**; only the
network awaits hop off-main. No background `ModelActor`.

## Signing out

PulseKit caches the feed on disk. When the user signs out, wipe it so nothing
from one account is left for the next:

```swift
PulseStore.wipeOnDisk()        // no live store at hand (main actor)
// or, on a store you hold:
store.wipeAll()
```

`reset()` is different: it clears the feed for a resync and keeps the "seen"
mark.

## The reference integration

`Demo/PulseLab` is a working host app (real mvServer login via MvAuth → real
mvPulse feed). It is **not** part of the package product — it's a separate Xcode
project that consumes PulseKit by local path. Use it as the living example of
how to wire `PulseConfig`, a resolver, and `PulseFeedView`.

## Versioning

Pre-1.0; the API will still move as it integrates. The DTOs are a **wire
contract** with a deployed mvPulse — when the contract changes, the package
version bumps, so a host can pin a PulseKit version that matches its backend.

## License

MIT — see [LICENSE](LICENSE).
