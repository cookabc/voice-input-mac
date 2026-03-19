// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "VoiceInputShell",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "VoiceInputShell", targets: ["VoiceInputShell"]),
    ],
    targets: [
        .executableTarget(
            name: "VoiceInputShell",
            path: "Sources",
            linkerSettings: [
                .linkedFramework("Speech"),
            ]
        ),
    ]
)
