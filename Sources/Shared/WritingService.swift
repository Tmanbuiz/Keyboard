import Foundation
import Security

struct WritingConnection: Codable {
    var endpoint: String
    var token: String
    var savedAt: Date? = nil
    var expiresAt: Date? = nil
    var appleUserID: String? = nil
    var valid: Bool {
        ServiceOrigin.accepts(endpoint) && !token.isEmpty && (expiresAt.map { $0 > Date() } ?? true)
    }
}

enum ConnectionVault {
    private static let service = "com.wiantribe.keyboard.writing"
    static var hasSharedStorage: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: KeyboardStore.appGroup) != nil
    }
    private static func query(shared: Bool) -> [String: Any] {
        var value: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "connection"]
        // Apple permits App Group identifiers as Keychain access groups. Only this app and its
        // entitled extensions can read the item; no credentials are written to UserDefaults/files.
        if shared { value[kSecAttrAccessGroup as String] = KeyboardStore.appGroup }
        return value
    }
    static func load() -> WritingConnection? {
        for shared in hasSharedStorage ? [true, false] : [false] {
            var lookup = query(shared: shared)
            lookup[kSecReturnData as String] = true; lookup[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            guard SecItemCopyMatching(lookup as CFDictionary, &result) == errSecSuccess,
                  let data = result as? Data,
                  let connection = try? JSONDecoder().decode(WritingConnection.self, from: data), connection.valid else { continue }
            if let revoked = KeyboardStore().writingRevokedAt, (connection.savedAt ?? .distantPast) <= revoked { continue }
            return connection
        }
        return nil
    }
    @discardableResult static func save(_ connection: WritingConnection?) -> Bool {
        guard var connection else {
            var success = true
            for shared in hasSharedStorage ? [true, false] : [false] {
                let result = SecItemDelete(query(shared: shared) as CFDictionary)
                if result != errSecSuccess && result != errSecItemNotFound { success = false }
            }
            KeyboardStore().writingRevokedAt = Date()
            return success
        }
        guard connection.valid else { return false }
        connection.savedAt = Date()
        guard let data = try? JSONEncoder().encode(connection) else { return false }
        let lookup = query(shared: hasSharedStorage)
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let updated = SecItemUpdate(lookup as CFDictionary, attributes as CFDictionary)
        var success = updated == errSecSuccess
        if updated == errSecItemNotFound {
            var insert = lookup; attributes.forEach { insert[$0.key] = $0.value }
            success = SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
        }
        return success
    }
}

enum WritingError: LocalizedError {
    case notConfigured, invalidText, rejected, invalidResponse, unauthorized, rateLimited, dailyLimit, unavailable
    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Your AI session expired or was revoked. Open WianTribe → AI account and sign in again."
        case .dailyLimit: return "Your daily AI allowance has been reached. It resets at midnight UTC."
        case .rateLimited: return "Too many requests. Wait a minute and try again."
        case .unavailable: return "Your AI service is unavailable. Try again later."
        case .notConfigured: return "Open WianTribe → AI account and sign in to use online AI."
        case .invalidText: return "Select or enter between 1 and 3,000 characters."
        case .rejected: return "The writing service rejected this request. Check the connection or try again later."
        case .invalidResponse: return "The writing service returned an invalid response."
        }
    }
}

enum WritingService {
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
        let (data, response) = try await BoundedHTTP.load(request, maximum: 100_000)
        switch response.statusCode {
        case 200...299: break
        case 401, 403: throw WritingError.unauthorized
        case 429:
            struct LimitResponse: Decodable { let code: String? }
            if (try? JSONDecoder().decode(LimitResponse.self, from: data).code) == "daily_limit" { throw WritingError.dailyLimit }
            throw WritingError.rateLimited
        case 500...599:
            throw WritingError.unavailable
        default: throw WritingError.rejected
        }
        guard data.count < 100_000, let decoded = try? JSONDecoder().decode(Response.self, from: data),
              !decoded.text.isEmpty, decoded.text.unicodeScalars.count <= 6000 else { throw WritingError.invalidResponse }
        return decoded.text
    }
}
