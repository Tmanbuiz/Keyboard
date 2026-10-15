import Foundation
import Security

struct WritingConnection: Codable {
    var endpoint: String
    var token: String
    var savedAt: Date? = nil
    var valid: Bool {
        guard let url = URL(string: endpoint) else { return false }
        return url.scheme == "https" && url.host != nil && url.user == nil && url.password == nil && !token.isEmpty
    }
}

enum ConnectionVault {
    private static let service = "com.wiantribe.keyboard.writing"
    static func load() -> WritingConnection? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service, kSecAttrAccount as String: "connection",
                                   kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        guard let connection = try? JSONDecoder().decode(WritingConnection.self, from: data) else { return nil }
        if let revoked = KeyboardStore().writingRevokedAt,
           (connection.savedAt ?? .distantPast) <= revoked { return nil }
        return connection
    }
    @discardableResult static func save(_ connection: WritingConnection?) -> Bool {
        if let connection, !connection.valid { return false }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service, kSecAttrAccount as String: "connection"]
        guard var connection else {
            let result = SecItemDelete(query as CFDictionary)
            guard result == errSecSuccess || result == errSecItemNotFound else { return false }
            KeyboardStore().writingRevokedAt = Date()
            return true
        }
        connection.savedAt = Date()
        guard connection.valid, let data = try? JSONEncoder().encode(connection) else { return false }
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let updated = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updated == errSecSuccess { return true }
        guard updated == errSecItemNotFound else { return false }
        var insert = query
        attributes.forEach { insert[$0.key] = $0.value }
        return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
    }
}

enum WritingError: LocalizedError {
    case notConfigured, invalidText, rejected, invalidResponse, unauthorized, rateLimited, unavailable
    var errorDescription: String? {
        switch self {
        case .unauthorized: return "The service token was rejected. Save the correct connection and reconnect the keyboard."
        case .rateLimited: return "Too many requests. Wait a minute and try again."
        case .unavailable: return "Your AI service is unavailable. Try again later."
        case .notConfigured: return "Connect your writing service first."
        case .invalidText: return "Select or enter between 1 and 3,000 characters."
        case .rejected: return "The writing service rejected this request. Check the connection or try again later."
        case .invalidResponse: return "The writing service returned an invalid response."
        }
    }
}

enum WritingService {
    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil) // Never forward selected text or a bearer token through a redirect.
        }
    }
    static func perform(text: String, action: WritingAction, language: KeyboardLanguage) async throws -> String {
        guard let connection = ConnectionVault.load(), connection.valid,
              let url = URL(string: connection.endpoint) else { throw WritingError.notConfigured }
        guard (1...3000).contains(text.unicodeScalars.count), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw WritingError.invalidText }
        struct Payload: Encodable { let text: String; let action: String; let language: String }
        struct Response: Decodable { let text: String }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(connection.token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(Payload(text: text, action: action.rawValue, language: language.rawValue))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw WritingError.invalidResponse }
        switch response.statusCode {
        case 200...299: break
        case 401, 403: throw WritingError.unauthorized
        case 429: throw WritingError.rateLimited
        case 500...599: throw WritingError.unavailable
        default: throw WritingError.rejected
        }
        guard data.count < 100_000, let decoded = try? JSONDecoder().decode(Response.self, from: data),
              !decoded.text.isEmpty, decoded.text.unicodeScalars.count <= 6000 else { throw WritingError.invalidResponse }
        return decoded.text
    }
}
