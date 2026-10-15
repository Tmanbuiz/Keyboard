// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WianTribeKeyboard",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "TypingCore", targets: ["TypingCore"])],
    targets: [
        .target(name: "TypingCore", path: "Sources/Core", resources: [.process("Resources")]),
        .target(name: "KeyboardStorage", dependencies: ["TypingCore"], path: "Sources/Shared",
                exclude: ["WritingService.swift", "GifService.swift", "OnDeviceWriting.swift"], sources: ["KeyboardStore.swift"]),
        .testTarget(name: "KeyboardStorageTests", dependencies: ["KeyboardStorage", "TypingCore"], path: "Tests/KeyboardStorageTests"),
        .testTarget(name: "TypingCoreTests", dependencies: ["TypingCore"], path: "Tests/TypingCoreTests")
    ]
)
