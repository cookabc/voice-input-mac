// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "Murmur",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v26),
    ],
    products: [
        .executable(name: "Murmur", targets: ["Murmur"]),
    ],
    targets: [
        .executableTarget(
            name: "Murmur",
            path: "Sources",
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("Speech"),
            ]
        ),
    ]
)
