import Foundation
import XCTest
@testable import InstallationDiagnostics

final class SigningInspectionTests: XCTestCase {
    func testMalformedDataIsRejected() {
        XCTAssertThrowsError(try SigningInspection.inspectExecutable(Data()))
        XCTAssertTrue((try! SigningInspection.inspectExecutable(Data(repeating: 0, count: 32))).contains("Unsupported"))
    }

    #if os(macOS)
    func testNativeSignedExecutableAndModifiedPage() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("main.c")
        let binary = folder.appendingPathComponent("probe")
        try "int main(void) { return 0; }\n".write(to: source, atomically: true, encoding: .utf8)
        func run(_ executable: String, _ arguments: [String]) throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            try process.run()
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0)
        }
        try run("/usr/bin/xcrun", ["clang", source.path, "-o", binary.path])
        try run("/usr/bin/codesign", ["--force", "--sign", "-", binary.path])
        var data = try Data(contentsOf: binary)
        let valid = try SigningInspection.inspectExecutable(data)
        XCTAssertTrue(valid.contains("mismatches: 0"), valid)
        data[4096] ^= 1
        let modified = try SigningInspection.inspectExecutable(data)
        XCTAssertTrue(modified.contains("mismatches: 1"), modified)
        XCTAssertThrowsError(try SigningInspection.inspectExecutable(Data(data.prefix(32))))
    }
    #endif
}
