// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WianTribeKeyboard",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "TypingCore", targets: ["TypingCore"])],
    targets: [
        .target(name: "GroqNetworking", dependencies: ["TypingCore"], path: "Sources/Shared",
                exclude: ["GifService.swift", "KeyboardStore.swift", "OnDeviceWriting.swift", "PersonalClipboardCapture.swift", "WritingService.swift", "WritingRouter.swift"], sources: ["GroqService.swift"]),
        .testTarget(name: "GroqNetworkingTests", dependencies: ["GroqNetworking", "TypingCore"], path: "Tests/GroqNetworkingTests"),
        .target(name: "InstallationDiagnostics", path: "Sources/Diagnostics"),
        .testTarget(name: "InstallationDiagnosticsTests", dependencies: ["InstallationDiagnostics"], path: "Tests/InstallationDiagnosticsTests"),
        .target(name: "TypingCore", path: "Sources/Core", resources: [.process("Resources")]),
        .testTarget(name: "TypingCoreTests", dependencies: ["TypingCore"], path: "Tests/TypingCoreTests")
    ]
)
