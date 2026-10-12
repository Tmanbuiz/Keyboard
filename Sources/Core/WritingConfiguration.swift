import Foundation

public enum WritingProvider: String, Codable, CaseIterable, Identifiable {
    case automatic, apple, groq, service
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .apple: return "Apple on this iPhone"
        case .groq: return "Groq"
        case .service: return "My writing service"
        }
    }
    public var shortTitle: String {
        switch self {
        case .automatic: return "Auto"
        case .apple: return "Apple"
        case .groq: return "Groq"
        case .service: return "My service"
        }
    }
    /// Only Automatic is allowed to fall back. An explicit choice stays with that provider.
    public var routes: [WritingRoute] {
        switch self {
        case .automatic: return [.onDevice, .service]
        case .apple: return [.onDevice]
        case .groq: return [.groq]
        case .service: return [.service]
        }
    }
}

public enum WritingRoute: Equatable { case onDevice, groq, service }

public struct GroqConfiguration: Codable, Equatable {
    public static let defaultModel = "openai/gpt-oss-20b"
    public static let suggestedModels = [defaultModel, "openai/gpt-oss-120b", "llama-3.3-70b-versatile", "llama-3.1-8b-instant"]
    public var key: String
    public var model: String
    public init(key: String, model: String = Self.defaultModel) {
        self.key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    public var valid: Bool {
        let keyCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-.")
        let modelCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-/.")
        return (8...512).contains(key.count) && key.unicodeScalars.allSatisfy(keyCharacters.contains)
            && (1...160).contains(model.count) && model.unicodeScalars.allSatisfy(modelCharacters.contains)
    }
}

/// Text edited inside the keyboard stays separate from the original text in the host app.
public struct WritingEditBuffer: Equatable {
    public private(set) var text: String
    public private(set) var cursor: Int
    public init(text: String) { self.text = text; cursor = text.count }
    public var before: String { String(text.prefix(cursor)) }
    public var after: String { String(text.dropFirst(cursor)) }
    public mutating func insert(_ value: String) {
        text = before + value + after
        cursor = min(text.count, cursor + value.count)
    }
    public mutating func delete() {
        guard cursor > 0 else { return }
        let prefix = String(before.dropLast())
        text = prefix + after; cursor = prefix.count
    }
    public mutating func move(_ offset: Int) { cursor = max(0, min(text.count, cursor + offset)) }
}
