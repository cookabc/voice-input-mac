// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Murmur",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "Murmur", targets: ["Murmur"]),
    ],
    targets: [
        .executableTarget(
            name: "Murmur",
            path: "Sources",
            linkerSettings: [
                .linkedFramework("Speech"),
            ]
        ),
    ]
)
