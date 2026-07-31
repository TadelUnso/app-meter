// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AppMeter",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AppMeterCore", targets: ["AppMeterCore"]),
        .executable(name: "AppMeter", targets: ["AppMeter"]),
    ],
    dependencies: [
        // The one third-party dependency, and a deliberate exception to this
        // project's zero-dependency rule: signed in-place updates for a macOS
        // app distributed outside the App Store have no reasonable substitute.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0"),
    ],
    targets: [
        .target(
            name: "AppMeterCore",
            path: "Sources/AppMeterCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "AppMeter",
            dependencies: [
                "AppMeterCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/AppMeter",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "AppMeterCoreTests",
            dependencies: ["AppMeterCore"],
            path: "Tests/AppMeterCoreTests",
            swiftSettings: [
                .swiftLanguageMode(.v5),
                // Swift Testing in Command Line Tools ships as a separate framework
                // (these flags are harmless with a full Xcode install)
                .unsafeFlags(["-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"]),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/usr/lib",
                ])
            ]
        ),
    ]
)
