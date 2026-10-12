import Foundation
import Security

/// Each sideloaded process keeps its own key. No new signing entitlements are required.
enum GroqVault {
    private static let service = "com.wiantribe.keyboard.groq"
    static func load() -> GroqConfiguration? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "connection",
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data,
              let value = try? JSONDecoder().decode(GroqConfiguration.self, from: data), value.valid else { return nil }
        return value
    }
    @discardableResult static func save(_ connection: GroqConfiguration?) -> Bool {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "connection"]
        guard let connection else {
            let status = SecItemDelete(query as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
        guard connection.valid, let data = try? JSONEncoder().encode(connection) else { return false }
        let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        return SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil) == errSecSuccess
    }
}

struct WritingConnectionTransfer: Codable {
    let kind: String
    let version: Int
    let provider: WritingProvider
    let groq: GroqConfiguration?
    let service: WritingConnection?
    init(provider: WritingProvider, groq: GroqConfiguration? = nil, service: WritingConnection? = nil) {
        kind = "wiantribe-ai-connection"; version = 1
        self.provider = provider; self.groq = groq; self.service = service
    }
    var valid: Bool {
        guard kind == "wiantribe-ai-connection", version == 1 else { return false }
        switch provider {
        case .groq: return groq?.valid == true && service == nil
        case .service, .automatic: return service?.valid == true && groq == nil
        case .apple: return groq == nil && service == nil
        }
    }
    @discardableResult func install() -> Bool {
        guard valid else { return false }
        switch provider {
        case .groq: return GroqVault.save(groq)
        case .automatic, .service: return ConnectionVault.save(service)
        case .apple: return true
        }
    }
}

struct WritingOutput {
    let text: String
    let provider: String
}

enum WritingRouter {
    static func perform(text: String, action: WritingAction, language: KeyboardLanguage, provider: WritingProvider,
                        allowOnline: Bool = true) async throws -> WritingOutput {
        var failure: Error = OnDeviceError.unavailable
        for route in provider.routes {
            try Task.checkCancellation()
            switch route {
            case .onDevice:
                do {
                    let result = action == .translate
                        ? try await OnDeviceWriting.translate(text, to: language)
                        : try await OnDeviceWriting.rewrite(text, action: action, language: language)
                    return WritingOutput(text: result, provider: "Apple on this iPhone")
                } catch {
                    try Task.checkCancellation()
                    failure = error
                }
            case .groq:
                guard allowOnline else { throw OnlineWritingError.fullAccess }
                guard let configuration = GroqVault.load() else { throw GroqError.notConfigured }
                #if DEBUG && targetEnvironment(simulator)
                // Public dummy key for the UI test's result/edit/replace flow. This branch
                // does not exist in the device Release IPA; networking is tested separately.
                if configuration.key == "gsk_WIANTRIBE_UI_TEST_ONLY" {
                    let draft = String(text.prefix(1)).uppercased() + text.dropFirst() + "."
                    return WritingOutput(text: draft, provider: "Groq UI test fixture")
                }
                #endif
                return WritingOutput(text: try await GroqService.perform(configuration: configuration, text: text, action: action, language: language), provider: "Groq")
            case .service:
                // Automatic does not hide the original Apple error behind an unconfigured service.
                if provider == .automatic && ConnectionVault.load() == nil { continue }
                guard allowOnline else { throw OnlineWritingError.fullAccess }
                return WritingOutput(text: try await WritingService.perform(text: text, action: action, language: language), provider: "My writing service")
            }
        }
        throw failure
    }
}

enum OnlineWritingError: LocalizedError {
    case fullAccess
    var errorDescription: String? { "Groq and online writing need Allow Full Access: Settings → General → Keyboard → Keyboards → WianTribe." }
}
