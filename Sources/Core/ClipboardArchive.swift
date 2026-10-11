import Foundation

/// A coordinated local file so the app, keyboard and notification reader do not
/// lose each other's captures when they save at the same time.
public final class ClipboardArchive {
    private let url: URL
    private let initial: [SavedPhrase]

    public init(url: URL, initial: [SavedPhrase] = []) {
        self.url = url
        self.initial = initial
    }

    public func read() throws -> [SavedPhrase] {
        guard FileManager.default.fileExists(atPath: url.path) else { return initial }
        var value: [SavedPhrase] = []
        var operationError: Error?
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &coordinationError) { path in
            do { value = try self.load(path) } catch { operationError = error }
        }
        if let error = coordinationError { throw error }
        if let error = operationError { throw error }
        return value
    }

    @discardableResult
    public func update(_ change: ([SavedPhrase]) -> [SavedPhrase]) throws -> [SavedPhrase] {
        var value: [SavedPhrase] = []
        var operationError: Error?
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: [], error: &coordinationError) { path in
            do {
                value = change(try self.load(path))
                let data = try JSONEncoder().encode(value)
                try data.write(to: path, options: .atomic)
            } catch { operationError = error }
        }
        if let error = coordinationError { throw error }
        if let error = operationError { throw error }
        return value
    }

    private func load(_ path: URL) throws -> [SavedPhrase] {
        guard FileManager.default.fileExists(atPath: path.path) else { return initial }
        return try JSONDecoder().decode([SavedPhrase].self, from: Data(contentsOf: path))
    }
}
