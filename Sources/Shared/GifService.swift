import Foundation

struct GifResult: Decodable, Equatable {
    let id: String
    let title: String?
    let preview: URL
    let url: URL
}

enum GifError: LocalizedError {
    case notConfigured, unavailable, tooLarge
    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Connect your WianTribe service in the app to search GIFs."
        case .unavailable: return "GIF search isn't available right now. Check the service has a GIPHY key."
        case .tooLarge: return "That GIF is too large to copy."
        }
    }
}

/// GIF search goes through the person's own WianTribe service, which holds the GIPHY key,
/// so no API key ships inside the app. Only the search words are sent.
enum GifService {
    private static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 20
        return URLSession(configuration: configuration)
    }

    static var isConfigured: Bool { ConnectionVault.load()?.valid == true }

    static func search(_ query: String, language: String) async throws -> [GifResult] {
        guard let connection = ConnectionVault.load(), connection.valid, var components = URLComponents(string: connection.endpoint) else {
            throw GifError.notConfigured
        }
        components.path = "/gifs"
        let trimmed = String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(50))
        components.queryItems = [URLQueryItem(name: "q", value: trimmed), URLQueryItem(name: "lang", value: language)]
        guard let url = components.url else { throw GifError.notConfigured }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(connection.token)", forHTTPHeaderField: "Authorization")
        let session = session(); defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode), data.count < 500_000 else { throw GifError.unavailable }
        struct Payload: Decodable { let gifs: [GifResult] }
        let gifs = try JSONDecoder().decode(Payload.self, from: data).gifs
        // Only GIPHY's media hosts are loaded, whatever the service returns.
        return gifs.filter { isTrusted($0.preview) && isTrusted($0.url) }
    }

    static func download(_ gif: GifResult) async throws -> Data {
        let session = session(); defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(from: gif.url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { throw GifError.unavailable }
        guard data.count < 8_000_000 else { throw GifError.tooLarge }
        return data
    }

    static func isTrusted(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return host == "giphy.com" || host.hasSuffix(".giphy.com")
    }
}
