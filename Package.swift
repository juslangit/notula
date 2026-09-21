// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Notula",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Notula",
            path: "Sources/Notula",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
