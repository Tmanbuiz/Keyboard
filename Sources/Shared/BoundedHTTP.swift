import Foundation

/// Each request owns a serial delegate queue. The lock also coordinates task cancellation.
final class BoundedHTTP: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    enum Failure: Error { case tooLarge, invalidResponse, redirect }
    private static let gate = RequestGate()
    private let maximum: Int
    private let lock = NSLock()
    private var buffer = Data()
    private var response: HTTPURLResponse?
    private var continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>?
    private var session: URLSession?
    private var finished = false

    private init(maximum: Int) { self.maximum = maximum }
    static func load(_ request: URLRequest, maximum: Int,
                     configuration: URLSessionConfiguration = .ephemeral) async throws -> (Data, HTTPURLResponse) {
        try await gate.acquire()
        do {
            let operation = BoundedHTTP(maximum: maximum)
            let result = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { operation.start(request, configuration: configuration, continuation: $0) }
            } onCancel: { operation.finish(.failure(CancellationError())) }
            await gate.release()
            return result
        } catch { await gate.release(); throw error }
    }

    private func start(_ request: URLRequest, configuration: URLSessionConfiguration,
                       continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); continuation.resume(throwing: CancellationError()); return }
        self.continuation = continuation
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 40
        configuration.httpMaximumConnectionsPerHost = 3
        let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        self.session = session
        let task = session.dataTask(with: request)
        lock.unlock()
        task.resume()
    }
    private func finish(_ result: Result<(Data, HTTPURLResponse), Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let continuation = self.continuation, session = self.session
        self.continuation = nil; self.session = nil; buffer = Data()
        lock.unlock()
        session?.invalidateAndCancel()
        continuation?.resume(with: result)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse else {
            completionHandler(.cancel); finish(.failure(Failure.invalidResponse)); return
        }
        guard response.expectedContentLength <= Int64(maximum) else {
            completionHandler(.cancel); finish(.failure(Failure.tooLarge)); return
        }
        lock.lock(); self.response = http; let stopped = finished; lock.unlock()
        completionHandler(stopped ? .cancel : .allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        guard data.count <= maximum - buffer.count else {
            lock.unlock(); finish(.failure(Failure.tooLarge)); return
        }
        buffer.append(data); lock.unlock()
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)); return }
        lock.lock(); let response = self.response, data = buffer; lock.unlock()
        if let response { finish(.success((data, response))) }
        else { finish(.failure(Failure.invalidResponse)) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil); finish(.failure(Failure.redirect))
    }
}

/// Caps aggregate buffered media, not only each individual response.
private actor RequestGate {
    private var active = 0
    private var waiting: [(UUID, CheckedContinuation<Void, Error>)] = []
    func acquire() async throws {
        try Task.checkCancellation()
        if active < 4 { active += 1; return }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()) }
                else { waiting.append((id, continuation)) }
            }
        } onCancel: { Task { await self.cancel(id) } }
    }
    private func cancel(_ id: UUID) {
        guard let index = waiting.firstIndex(where: { $0.0 == id }) else { return }
        waiting.remove(at: index).1.resume(throwing: CancellationError())
    }
    func release() {
        if waiting.isEmpty { active -= 1 }
        else { waiting.removeFirst().1.resume() }
    }
}
