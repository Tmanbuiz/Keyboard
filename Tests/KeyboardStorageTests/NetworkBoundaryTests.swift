import XCTest
@testable import KeyboardStorage

final class NetworkBoundaryTests: XCTestCase {
    func testOriginRejectsLookalikesCredentialsPortsAndAlternatePaths() {
        XCTAssertTrue(ServiceOrigin.accepts("https://keyboard.atoyejet.workers.dev/write"))
        XCTAssertTrue(ServiceOrigin.accepts("https://keyboard.atoyejet.workers.dev:443/write"))
        for endpoint in ["http://keyboard.atoyejet.workers.dev/write", "https://keyboard.atoyejet.workers.dev.evil.test/write",
                         "https://evil.test/write", "https://user@keyboard.atoyejet.workers.dev/write",
                         "https://keyboard.atoyejet.workers.dev:444/write", "https://keyboard.atoyejet.workers.dev/other",
                         "https://keyboard.atoyejet.workers.dev/write?target=evil", "https://keyboard.atoyejet.workers.dev/write#evil"] {
            XCTAssertFalse(ServiceOrigin.accepts(endpoint), endpoint)
        }
    }
    private func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StreamingFixture.self]
        return configuration
    }
    func testValidResponseAndUnadvertisedOversizedBodies() async throws {
        let result = try await BoundedHTTP.load(URLRequest(url: URL(string: "https://fixture.test/valid")!), maximum: 8_000_000, configuration: configuration())
        XCTAssertEqual(result.0.count, 32_768)
        for size in [9_000_000, 100_000_000] {
            do {
                _ = try await BoundedHTTP.load(URLRequest(url: URL(string: "https://fixture.test/\(size)")!), maximum: 8_000_000, configuration: configuration())
                XCTFail("Oversized chunked response was accepted")
            } catch BoundedHTTP.Failure.tooLarge { }
        }
    }
    func testAdvertisedOversizeAndInterruptedTransfer() async {
        for path in ["advertised", "interrupted"] {
            do {
                _ = try await BoundedHTTP.load(URLRequest(url: URL(string: "https://fixture.test/\(path)")!), maximum: 8_000_000, configuration: configuration())
                XCTFail("Invalid transfer accepted")
            } catch { }
        }
    }
    func testCancellationDoesNotLeaveARequestSlotOccupied() async throws {
        let task = Task { try await BoundedHTTP.load(URLRequest(url: URL(string: "https://fixture.test/slow")!), maximum: 1000, configuration: configuration()) }
        try await Task.sleep(nanoseconds: 30_000_000)
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled request succeeded") } catch { }
        for _ in 0..<5 {
            _ = try await BoundedHTTP.load(URLRequest(url: URL(string: "https://fixture.test/valid")!), maximum: 50_000, configuration: configuration())
        }
    }
}

/// Delivers one chunk at a time and waits for its delegate to cancel on overage.
private final class StreamingFixture: URLProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() { lock.lock(); stopped = true; lock.unlock() }
    private var isStopped: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
    override func startLoading() {
        DispatchQueue.global().async { [self] in
            let path = request.url!.lastPathComponent
            let headers = path == "advertised" ? ["Content-Length": "100000000"] : [:]
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: headers)!, cacheStoragePolicy: .notAllowed)
            if path == "slow" { return }
            if path == "interrupted" { client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost)); return }
            let count = Int(path) ?? 32_768
            var sent = 0
            while sent < count && !isStopped {
                let length = min(32_768, count - sent)
                client?.urlProtocol(self, didLoad: Data(repeating: 1, count: length)); sent += length
                Thread.sleep(forTimeInterval: 0.001)
            }
            if !isStopped { client?.urlProtocolDidFinishLoading(self) }
        }
    }
}
