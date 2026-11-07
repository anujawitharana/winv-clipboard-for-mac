// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "WinVClipboard",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "WinVClipboard", targets: ["WinVClipboard"])
    ],
    targets: [
        .executableTarget(
            name: "WinVClipboard",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("Carbon"),
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .testTarget(
            name: "WinVClipboardTests",
            dependencies: ["WinVClipboard"]
        )
    ]
)
