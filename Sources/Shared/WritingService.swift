import Foundation
import Security

struct WritingConnection: Codable {
    var endpoint: String
    var token: String
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
        return try? JSONDecoder().decode(WritingConnection.self, from: data)
    }
    @discardableResult static func save(_ connection: WritingConnection?) -> Bool {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service, kSecAttrAccount as String: "connection"]
        SecItemDelete(query as CFDictionary)
        guard let connection else { return true }
        guard connection.valid, let data = try? JSONEncoder().encode(connection) else { return false }
        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
    }
}

enum WritingError: LocalizedError {
    case notConfigured, invalidText, rejected, invalidResponse
    var errorDescription: String? {
        switch self {
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
        guard (1...3000).contains(text.count), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw WritingError.invalidText }
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
        guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode) else { throw WritingError.rejected }
        guard data.count < 100_000, let decoded = try? JSONDecoder().decode(Response.self, from: data),
              !decoded.text.isEmpty, decoded.text.count <= 6000 else { throw WritingError.invalidResponse }
        return decoded.text
    }
}
