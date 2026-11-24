// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "NucleantAudio",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        // Audio file loading and playback, with one API on every platform.
        .library(
            name: "NucleantAudio",
            targets: ["NucleantAudio"]
        ),
        // The protocols and values alone (`AudioProcessor`, `AudioClip`, …),
        // for a package that makes sound without playing it, as NucleantDSP
        // does: what it writes then plays through NucleantAudio everywhere,
        // without it ever depending on a platform target.
        .library(
            name: "AudioProtocols",
            targets: ["AudioProtocols"]
        ),
    ],
    dependencies: [
        // WasmAudio's only; resolved everywhere, built for wasm alone.
        .package(url: "https://github.com/swiftwasm/JavaScriptKit.git", from: "0.63.0"),
    ],
    targets: [
        // What the platform targets and NucleantAudio share.
        .target(
            name: "AudioProtocols"
        ),
        // One per platform, each declaring the same `DefaultAudioOutput` and
        // `DefaultAudioDecoder`. A build compiles only the one its platform
        // condition below picks, so their files need no `#if os(...)` of
        // their own — except where a target spans several OSes (AppleAudio's
        // output, per OS).
        // AAudio and the NDK's media codecs: their headers in the Swift
        // Android SDK's sysroot, through a module map.
        .systemLibrary(
            name: "CAndroidAudio"
        ),
        .target(
            name: "AndroidAudio",
            dependencies: ["AudioProtocols", "CAndroidAudio"]
        ),
        .target(
            name: "LinuxAudio",
            dependencies: ["AudioProtocols"],
            linkerSettings: [
                // libasound and libsndfile are opened with dlopen, so
                // building needs neither library's headers.
                .linkedLibrary("dl"),
            ]
        ),
        .target(
            name: "AppleAudio",
            dependencies: ["AudioProtocols"]
        ),
        // Web Audio, reached through JavaScriptKit.
        .target(
            name: "WasmAudio",
            dependencies: [
                "AudioProtocols",
                .product(name: "JavaScriptKit", package: "JavaScriptKit"),
            ],
            // `@_extern(wasm)`: the page's `await_promise`, which the decoder
            // waits on `decodeAudioData` with.
            swiftSettings: [.enableExperimentalFeature("Extern")]
        ),
        .target(
            name: "WindowsAudio",
            dependencies: ["AudioProtocols"]
        ),
        .target(
            name: "NucleantAudio",
            dependencies: [
                "AudioProtocols",
                .byName(name: "LinuxAudio", condition: .when(platforms: [.linux])),
                .byName(name: "AndroidAudio", condition: .when(platforms: [.android])),
                .byName(name: "AppleAudio", condition: .when(platforms: [.macOS, .iOS, .visionOS, .tvOS, .watchOS])),
                .byName(name: "WasmAudio", condition: .when(platforms: [.wasi])),
                .byName(name: "WindowsAudio", condition: .when(platforms: [.windows])),
            ]
        ),
        .testTarget(
            name: "NucleantAudioTests",
            dependencies: ["NucleantAudio"],
            // Files read back, rather than written by the tests: a browser's
            // file system is read-only.
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
