// swift-tools-version: 6.2
import PackageDescription

// PulseKit — the chat-side Pulse feature as a self-contained SPM: wire DTOs,
// REST transport, SwiftData persistence, pull-sync, and the embedded feed UI.
// Talks to mvPulse (pulse.mvchat.app). A host app adds a thin wrapper.
//
// Swift 6 strict concurrency from line one — NOT v5-with-a-TODO. If something
// won't compile under complete checking, we fix the design, not the flag.
let package = Package(
    name: "PulseKit",
    platforms: [.iOS(.v26)], // iOS-only — the consumer is the iOS app (PulseLab or a host app)
    products: [
        .library(name: "PulseKit", targets: ["PulseKit"]),
    ],
    targets: [
        .target(
            name: "PulseKit",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "PulseKitTests",
            dependencies: ["PulseKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
