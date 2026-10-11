import Foundation

public enum KeyboardLanguage: String, Codable, CaseIterable, Identifiable {
    case english, yoruba, pidgin
    public var id: String { rawValue }
    public var title: String {
        switch self { case .english: return "English"; case .yoruba: return "Yorùbá"; case .pidgin: return "Naija Pidgin" }
    }
    public var shortTitle: String {
        switch self { case .english: return "EN"; case .yoruba: return "YO"; case .pidgin: return "NG" }
    }
    public var speechLocale: String { self == .yoruba ? "yo-NG" : "en-NG" }
}

public enum KeyboardTheme: String, Codable, CaseIterable, Identifiable {
    case ocean, midnight, light, rose
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

public enum HandMode: String, Codable, CaseIterable, Identifiable {
    case full, left, right
    public var id: String { rawValue }
    public var title: String { self == .full ? "Both hands" : "\(rawValue.capitalized) hand" }
}

public struct KeyboardPreferences: Codable, Equatable {
    public var language: KeyboardLanguage = .english
    public var theme: KeyboardTheme = .ocean
    public var handMode: HandMode = .full
    public var numberRow = true
    public var autocorrect = true
    public var predictions = true
    public var swipeTyping = true
    public var autoCapitalization = true
    public var doubleSpacePeriod = true
    public var haptics = false
    // Word learning is opt-in; never retain sentences or a keystroke history.
    public var learnWords = false
    public var height: Double = 300
    // Clipboard history is opt-in and stays on this device.
    public var clipboardHistory = false
    public var clipboardDays = 7
    public init() {}

    // Missing keys fall back to defaults, so adding a setting never resets existing ones.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = KeyboardPreferences()
        language = (try? c.decodeIfPresent(KeyboardLanguage.self, forKey: .language)) ?? d.language
        theme = (try? c.decodeIfPresent(KeyboardTheme.self, forKey: .theme)) ?? d.theme
        handMode = (try? c.decodeIfPresent(HandMode.self, forKey: .handMode)) ?? d.handMode
        numberRow = (try? c.decodeIfPresent(Bool.self, forKey: .numberRow)) ?? d.numberRow
        autocorrect = (try? c.decodeIfPresent(Bool.self, forKey: .autocorrect)) ?? d.autocorrect
        predictions = (try? c.decodeIfPresent(Bool.self, forKey: .predictions)) ?? d.predictions
        swipeTyping = (try? c.decodeIfPresent(Bool.self, forKey: .swipeTyping)) ?? d.swipeTyping
        autoCapitalization = (try? c.decodeIfPresent(Bool.self, forKey: .autoCapitalization)) ?? d.autoCapitalization
        doubleSpacePeriod = (try? c.decodeIfPresent(Bool.self, forKey: .doubleSpacePeriod)) ?? d.doubleSpacePeriod
        haptics = (try? c.decodeIfPresent(Bool.self, forKey: .haptics)) ?? d.haptics
        learnWords = (try? c.decodeIfPresent(Bool.self, forKey: .learnWords)) ?? d.learnWords
        height = (try? c.decodeIfPresent(Double.self, forKey: .height)) ?? d.height
        clipboardHistory = (try? c.decodeIfPresent(Bool.self, forKey: .clipboardHistory)) ?? d.clipboardHistory
        clipboardDays = (try? c.decodeIfPresent(Int.self, forKey: .clipboardDays)) ?? d.clipboardDays
    }
}

/// A clipboard item. Pinned items are saved phrases: they never expire.
public struct SavedPhrase: Codable, Identifiable, Equatable {
    public var id: UUID
    public var text: String
    public var pinned: Bool
    public var createdAt: Date
    public init(text: String, pinned: Bool = false, createdAt: Date = Date()) {
        id = UUID(); self.text = String(text.prefix(ClipboardHistory.maxLength)); self.pinned = pinned; self.createdAt = createdAt
    }
}

public enum WritingAction: String, Codable, CaseIterable, Identifiable {
    case grammar, professional, casual, translate
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

public enum TextContext {
    public static func isWordCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy {
            CharacterSet.letters.contains($0) || CharacterSet.nonBaseCharacters.contains($0)
                || $0 == "'" || $0 == "’"
        }
    }

    public static func currentWord(in text: String) -> String {
        String(text.reversed().prefix(while: isWordCharacter).reversed())
    }

    public static func previousWord(in text: String) -> String {
        let current = currentWord(in: text)
        let prefix = String(text.dropLast(current.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        return currentWord(in: prefix).lowercased()
    }

    public static func shouldCapitalize(after text: String) -> Bool {
        if text.isEmpty || text.hasSuffix("\n") { return true }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return [".", "!", "?"].contains(String(trimmed.suffix(1))) && trimmed.count < text.count
    }

    public static func matchingCase(_ candidate: String, to original: String) -> String {
        if !original.isEmpty && original == original.uppercased() { return candidate.uppercased() }
        if original.first?.isUppercase == true { return candidate.prefix(1).uppercased() + candidate.dropFirst() }
        return candidate
    }

    public static func canLearn(_ word: String) -> Bool {
        let letters = word.filter { $0.isLetter }
        return (2...24).contains(word.count) && letters.count == word.count
            && word == word.lowercased() && !word.contains("@")
    }
}

// Undo is allowed only if the cursor still follows this exact correction.
public struct CorrectionRecord: Equatable {
    public let original: String
    public let replacement: String
    public let contextSuffix: String
    public init(original: String, replacement: String, contextBefore: String) {
        self.original = original; self.replacement = replacement
        contextSuffix = String((String(contextBefore.dropLast(original.count)) + replacement + " ").suffix(64))
    }
    public func canUndo(context: String) -> Bool { context.hasSuffix(contextSuffix) }
}
