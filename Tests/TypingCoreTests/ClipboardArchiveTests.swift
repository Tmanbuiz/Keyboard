import Foundation
import XCTest
@testable import TypingCore

final class ClipboardArchiveTests: XCTestCase {
    private func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    func testSeparateReadersSeeDurableCapturesAndClear() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("clips.json")
        let app = ClipboardArchive(url: url)
        let reader = ClipboardArchive(url: url)
        XCTAssertTrue(try app.read().isEmpty)
        try app.update { ClipboardHistory.adding("saved copy", to: $0, pinned: true) }
        XCTAssertEqual(try reader.read().map(\.text), ["saved copy"])
        try reader.update { _ in [] }
        XCTAssertTrue(try app.read().isEmpty)
    }

    func testCoordinatedWritersKeepAllCopies() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("clips.json")
        let lock = NSLock()
        var failures = 0
        DispatchQueue.concurrentPerform(iterations: 24) { index in
            do {
                let archive = ClipboardArchive(url: url)
                try archive.update { ClipboardHistory.adding("copy \(index)", to: $0) }
            } catch { lock.lock(); failures += 1; lock.unlock() }
        }
        XCTAssertEqual(failures, 0)
        let copies = try ClipboardArchive(url: url).read()
        XCTAssertEqual(Set(copies.map(\.text)).count, 24)
    }

    func testCorruptHistoryIsNotSilentlyOverwritten() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("clips.json")
        let damaged = Data("invalid history".utf8)
        try damaged.write(to: url)
        let archive = ClipboardArchive(url: url)
        XCTAssertThrowsError(try archive.update { ClipboardHistory.adding("new copy", to: $0) })
        XCTAssertEqual(try Data(contentsOf: url), damaged)
    }
}
