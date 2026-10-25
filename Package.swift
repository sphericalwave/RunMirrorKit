// swift-tools-version: 6.2
import PackageDescription

/// Built the way the apps build their own code: main-actor by default, with
/// approachable concurrency, in the Swift 5 language mode.
let settings: [SwiftSetting] = [
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("InferSendableFromCaptures"),
    .enableUpcomingFeature("GlobalActorIsolatedTypesUsability"),
    .enableUpcomingFeature("DisableOutwardActorInference"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .swiftLanguageMode(.v5),
]

let package = Package(
    name: "RunMirrorKit",
    platforms: [.iOS(.v17), .macOS(.v14), .watchOS(.v10)],
    products: [
        /// What the phone and the watch say to each other, and the rules both
        /// sides apply. Every platform.
        .library(name: "RunMirrorKit", targets: ["RunMirrorKit"]),
        /// The phone's end: the run's audio, Now Playing controls, and the
        /// link to the watch. iOS (and a do-nothing macOS stand-in).
        .library(name: "RunMirrorPhone", targets: ["RunMirrorPhone"]),
        /// The watch app's run screens, haptics and workout session. watchOS.
        .library(name: "RunMirrorWatch", targets: ["RunMirrorWatch"]),
    ],
    targets: [
        .target(name: "RunMirrorKit", swiftSettings: settings),
        .target(name: "RunMirrorPhone", dependencies: ["RunMirrorKit"], swiftSettings: settings),
        .target(name: "RunMirrorWatch", dependencies: ["RunMirrorKit"], swiftSettings: settings),
        .testTarget(name: "RunMirrorKitTests", dependencies: ["RunMirrorKit"], swiftSettings: settings),
    ]
)
