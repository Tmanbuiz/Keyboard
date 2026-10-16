import Foundation
import ImageIO

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
        case .notConfigured: return "Sign in in WianTribe → Tools → AI account to search GIFs."
        case .unavailable: return "GIF search isn't available right now. Check the service has a GIPHY key."
        case .tooLarge: return "That GIF is too large to copy."
        }
    }
}

/// GIF search goes through the person's own WianTribe service, which holds the GIPHY key,
/// so no API key ships inside the app. Only the search words are sent.
enum GifService {
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
        let (data, response) = try await BoundedHTTP.load(request, maximum: 500_000)
        guard (200...299).contains(response.statusCode) else { throw GifError.unavailable }
        struct Payload: Decodable { let gifs: [GifResult] }
        let gifs = try JSONDecoder().decode(Payload.self, from: data).gifs
        // Only GIPHY's media hosts are loaded, whatever the service returns.
        return gifs.filter { isTrusted($0.preview) && isTrusted($0.url) }
    }

    static func download(_ gif: GifResult) async throws -> Data {
        guard isTrusted(gif.url) else { throw GifError.unavailable }
        let data: Data
        do {
            let result = try await BoundedHTTP.load(URLRequest(url: gif.url), maximum: 8_000_000)
            guard (200...299).contains(result.1.statusCode) else { throw GifError.unavailable }
            data = result.0
        } catch BoundedHTTP.Failure.tooLarge { throw GifError.tooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetType(source) as String? == "com.compuserve.gif",
              CGImageSourceGetCount(source) > 0, CGImageSourceGetCount(source) <= 200 else { throw GifError.tooLarge }
        var pixels = 0
        for index in 0..<CGImageSourceGetCount(source) {
            guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  width > 0, height > 0, width <= 2048, height <= 2048 else { throw GifError.tooLarge }
            pixels += width * height
            guard pixels <= 80_000_000 else { throw GifError.tooLarge }
        }
        return data
    }

    static func isTrusted(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil, url.port == nil || url.port == 443, let host = url.host?.lowercased() else { return false }
        return host == "giphy.com" || host.hasSuffix(".giphy.com")
    }
}
