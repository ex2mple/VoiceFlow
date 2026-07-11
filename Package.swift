// swift-tools-version:5.9
import PackageDescription

// Static whisper.cpp libs are built by scripts/build-whisper.sh into vendor/whisper/lib.
let whisperLink: [LinkerSetting] = [
    .unsafeFlags(["-Lvendor/whisper/lib"]),
    .linkedLibrary("whisper"),
    .linkedLibrary("ggml"),
    .linkedLibrary("ggml-metal"),
    .linkedLibrary("ggml-blas"),
    .linkedLibrary("ggml-cpu"),
    .linkedLibrary("ggml-base"),
    .linkedLibrary("c++"),
    .linkedFramework("Metal"),
    .linkedFramework("MetalKit"),
    .linkedFramework("Accelerate"),
    .linkedFramework("Foundation"),
]

let package = Package(
    name: "VoiceFlow",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CWhisper"),
        .target(
            name: "VoiceFlowCore",
            dependencies: ["CWhisper"]
        ),
        .executableTarget(
            name: "VoiceFlow",
            dependencies: ["VoiceFlowCore"],
            linkerSettings: whisperLink
        ),
        .executableTarget(
            name: "voiceflow-tests",
            dependencies: ["VoiceFlowCore"],
            path: "Tests/VoiceFlowTests",
            linkerSettings: whisperLink
        ),
    ]
)
