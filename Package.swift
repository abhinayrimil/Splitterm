// swift-tools-version:5.10
// Splitterm — a native macOS terminal modelled on GNOME Terminator.
import PackageDescription

let package = Package(
    name: "Splitterm",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Splitterm", targets: ["Splitterm"]),
    ],
    dependencies: [
        // SwiftTerm 1.20.0, vendored with one change: Shaders.metal is a .copy resource, so no `metal`
        // compiler (full Xcode) is needed. Stay on 1.20.x: 1.99+ needs the Swift 6.2 toolchain.
        .package(path: "Vendor/SwiftTerm"),
    ],
    targets: [
        // Pure model code (Foundation only) so it can be unit tested without AppKit.
        .target(
            name: "SplittermCore",
            path: "Sources/SplittermCore"
        ),
        .executableTarget(
            name: "Splitterm",
            dependencies: [
                "SplittermCore",
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ],
            path: "Sources/Splitterm"
        ),
        .testTarget(
            name: "SplittermCoreTests",
            dependencies: ["SplittermCore"],
            path: "Tests/SplittermCoreTests"
        ),
    ]
)
