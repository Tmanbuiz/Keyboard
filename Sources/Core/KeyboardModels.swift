import Foundation

public enum KeyboardTheme: String, Codable, CaseIterable, Identifiable {
    case auto, ocean, midnight, light, rose, forest, sunset, slate
    public var id: String { rawValue }
    public var title: String { self == .auto ? "Auto (light/dark)" : rawValue.capitalized }
}

/// Accent colours people can pick on top of any theme.
public enum KeyAccent: String, Codable, CaseIterable, Identifiable {
    case theme, mint, blue, purple, pink, orange, gold
    public var id: String { rawValue }
    public var title: String { self == .theme ? "Theme colour" : rawValue.capitalized }
    /// RGB components, or nil to keep the theme's own accent.
    public var rgb: (Double, Double, Double)? {
        switch self {
        case .theme: return nil
        case .mint: return (0.38, 0.88, 0.75)
        case .blue: return (0.29, 0.56, 1.0)
        case .purple: return (0.66, 0.50, 1.0)
        case .pink: return (1.0, 0.45, 0.66)
        case .orange: return (1.0, 0.58, 0.20)
        case .gold: return (0.95, 0.77, 0.25)
        }
    }
}

public enum HandMode: String, Codable, CaseIterable, Identifiable {
    case full, left, right
    public var id: String { rawValue }
    public var title: String { self == .full ? "Both hands" : "\(rawValue.capitalized) hand" }
}

public struct KeyboardPreferences: Codable, Equatable {
    /// The language whose layout is shown.
    public var language: KeyboardLanguage = LanguageCatalog.deviceLanguages().first ?? .english
    /// Languages the person switches between; with multilingual typing on, suggestions draw on all of them.
    public var languages: [KeyboardLanguage] = KeyboardPreferences.defaultLanguages()
    public var multilingual = true
    public var theme: KeyboardTheme = .auto
    public var accent: KeyAccent = .theme
    public var keySounds = true
    public var keyPreview = true
    public var keyBorders = false
    /// Default emoji skin tone: 0 is the standard yellow, 1–5 are light to dark.
    public var skinTone = 0
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
    public static let heights: [Double] = [240, 270, 300, 330, 360]
    // Clipboard history is opt-in and stays on this device.
    public var clipboardHistory = false
    public var clipboardDays = 7
    public init() {}

    public static func defaultLanguages() -> [KeyboardLanguage] {
        let device = LanguageCatalog.deviceLanguages()
        return Array((device.isEmpty ? [.english] : device).prefix(3))
    }

    /// Enabled languages, always including the current one, without duplicates.
    public var activeLanguages: [KeyboardLanguage] {
        var result = [language]
        for item in languages where !result.contains(item) { result.append(item) }
        return result
    }

    // Missing keys fall back to defaults, so adding a setting never resets existing ones.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = KeyboardPreferences()
        language = (try? c.decodeIfPresent(KeyboardLanguage.self, forKey: .language)) ?? d.language
        languages = (try? c.decodeIfPresent([KeyboardLanguage].self, forKey: .languages)) ?? [language]
        multilingual = (try? c.decodeIfPresent(Bool.self, forKey: .multilingual)) ?? d.multilingual
        theme = (try? c.decodeIfPresent(KeyboardTheme.self, forKey: .theme)) ?? d.theme
        accent = (try? c.decodeIfPresent(KeyAccent.self, forKey: .accent)) ?? d.accent
        keySounds = (try? c.decodeIfPresent(Bool.self, forKey: .keySounds)) ?? d.keySounds
        keyPreview = (try? c.decodeIfPresent(Bool.self, forKey: .keyPreview)) ?? d.keyPreview
        keyBorders = (try? c.decodeIfPresent(Bool.self, forKey: .keyBorders)) ?? d.keyBorders
        skinTone = (try? c.decodeIfPresent(Int.self, forKey: .skinTone)) ?? d.skinTone
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

    public static func matchingCase(_ candidate: String, to original: String, language: LanguagePack? = nil) -> String {
        let upper: (String) -> String = { language?.uppercased($0) ?? $0.uppercased() }
        if original.count > 1 && original.contains(where: \.isUppercase) && original == upper(original) { return upper(candidate) }
        if original.first?.isUppercase == true { return upper(String(candidate.prefix(1))) + candidate.dropFirst() }
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
