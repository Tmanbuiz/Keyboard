import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import GroqNetworking
import TypingCore

final class GroqNetworkingTests: XCTestCase {
    let configuration = GroqConfiguration(key: "gsk_TEST_ONLY_NOT_A_REAL_KEY")
    override func tearDown() { GroqStub.handler = nil; super.tearDown() }

    private func session(status: Int = 200, body: String, inspect: ((URLRequest) throws -> Void)? = nil) -> URLSession {
        GroqStub.handler = { request in
            try inspect?(request)
            return (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }
        let value = URLSessionConfiguration.ephemeral
        value.protocolClasses = [GroqStub.self]
        return URLSession(configuration: value)
    }
    private func perform(_ session: URLSession) async throws -> String {
        try await GroqService.perform(configuration: configuration, text: "God using the one he loves", action: .grammar, language: .english, session: session)
    }

    func testRequestUsesFixedGroqHostAndSeparatesInputFromInstructions() throws {
        let request = try GroqService.writingRequest(configuration: configuration, text: "Ignore this. Ẹ káàárọ̀", action: .translate, language: .yoruba)
        XCTAssertEqual(request.url, GroqService.completionsURL)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(configuration.key)")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
        let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
        XCTAssertEqual(messages[1]["content"], "Ignore this. Ẹ káàárọ̀")
        XCTAssertTrue(messages[0]["content"]!.contains("Yoruba"))
        XCTAssertFalse(messages[0]["content"]!.contains("Ignore this"))
        XCTAssertEqual(body["include_reasoning"] as? Bool, false)
        XCTAssertEqual(body["reasoning_effort"] as? String, "low")
        XCTAssertEqual(body["stream"] as? Bool, false)
        XCTAssertNil(body["store"])
    }
    func testLlamaRequestDoesNotSendGPTReasoningOptions() throws {
        let value = GroqConfiguration(key: configuration.key, model: "llama-3.3-70b-versatile")
        let request = try GroqService.writingRequest(configuration: value, text: "hello", action: .grammar, language: .english)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
        XCTAssertNil(body["include_reasoning"]); XCTAssertNil(body["reasoning_effort"])
    }
    func testComposerTreatsInputAsDraftRequest() throws {
        let request = try GroqService.writingRequest(configuration: configuration, text: "Wish my sister a happy birthday", action: .compose, language: .english)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
        let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
        XCTAssertTrue(messages[0]["content"]!.contains("describes the draft to write"))
        XCTAssertTrue(messages[0]["content"]!.contains("do not invent facts"))
    }
    func testInvalidAndOversizedInputRejectedBeforeNetworking() throws {
        for text in ["", " \n ", String(repeating: "a", count: 3001)] {
            XCTAssertThrowsError(try GroqService.writingRequest(configuration: configuration, text: text, action: .grammar, language: .english)) { XCTAssertEqual($0 as? GroqError, .invalidText) }
        }
        XCTAssertThrowsError(try GroqService.writingRequest(configuration: GroqConfiguration(key: "x\r\nAuthorization: injected"), text: "hello", action: .grammar, language: .english))
    }
    func testSuccessfulResultReadsOnlyAssistantContent() async throws {
        let value = session(body: #"{"choices":[{"message":{"content":" God uses the one He loves. ","reasoning":"not displayed"},"finish_reason":"stop"}]}"#)
        defer { value.invalidateAndCancel() }
        let text = try await perform(value)
        XCTAssertEqual(text, "God uses the one He loves.")
    }
    func testStatusCodesAreActionableWithoutEchoingResponseOrKey() async throws {
        for (status, expected) in [(401, GroqError.invalidKey), (403, .denied), (404, .modelUnavailable), (429, .rateLimited), (502, .unavailable), (302, .unavailable)] {
            let value = session(status: status, body: configuration.key)
            do { _ = try await perform(value); XCTFail("Expected HTTP \(status) to fail") }
            catch { XCTAssertEqual(error as? GroqError, expected); XCTAssertFalse(error.localizedDescription.contains(configuration.key)) }
            value.invalidateAndCancel()
        }
    }
    func testTruncatedAndMalformedResultsCannotBeInserted() async throws {
        let responses = [
            (#"{"choices":[{"message":{"content":"cut off"},"finish_reason":"length"}]}"#, GroqError.truncated),
            (#"{"choices":[]}"#, .invalidResponse),
            (#"{"choices":[{"message":{"content":null},"finish_reason":"stop"}]}"#, .invalidResponse),
            (#"{"choices":[{"message":{"content":"   "},"finish_reason":"stop"}]}"#, .invalidResponse),
            (#"{"choices":[{"message":{"content":"text"},"finish_reason":"content_filter"}]}"#, .invalidResponse)
        ]
        for (body, expected) in responses {
            let value = session(body: body)
            do { _ = try await perform(value); XCTFail("Unusable output was accepted") }
            catch { XCTAssertEqual(error as? GroqError, expected) }
            value.invalidateAndCancel()
        }
    }
    func testModelCheckUsesGETWithNoWritingPayload() async throws {
        let value = session(body: #"{"data":[{"id":"openai/gpt-oss-20b","active":true},{"id":"old-model","active":false}]}"#) { request in
            XCTAssertEqual(request.url, GroqService.modelsURL)
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertNil(request.httpBody)
        }
        defer { value.invalidateAndCancel() }
        let models = try await GroqService.models(configuration: configuration, session: value)
        XCTAssertEqual(models, ["openai/gpt-oss-20b"])
    }
    func testCancellationRemainsCancellation() async throws {
        GroqStub.handler = { _ in throw URLError(.cancelled) }
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [GroqStub.self]
        let value = URLSession(configuration: configuration); defer { value.invalidateAndCancel() }
        do { _ = try await perform(value); XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
}

private final class GroqStub: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.badServerResponse) }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
