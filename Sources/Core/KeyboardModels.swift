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
    public var aiEngine: AIEngine = .auto
    public var handMode: HandMode = .full
    public var numberRow = true
    public var autocorrect = true
    public var predictions = true
    /// Offer emoji in the suggestion bar for words like "love" or "pizza".
    public var emojiPredictions = true
    public var swipeTyping = true
    public var autoCapitalization = true
    public var doubleSpacePeriod = true
    public var haptics = false
    // Word learning is opt-in; never retain sentences or a keystroke history.
    public var learnWords = false
    public var height: Double = 300
    public static let heights: [Double] = [240, 270, 300, 330, 360]
    // Clipboard history is opt-in and stays on this device.
    public var privateMode = false
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
        aiEngine = (try? c.decodeIfPresent(AIEngine.self, forKey: .aiEngine)) ?? d.aiEngine
        handMode = (try? c.decodeIfPresent(HandMode.self, forKey: .handMode)) ?? d.handMode
        numberRow = (try? c.decodeIfPresent(Bool.self, forKey: .numberRow)) ?? d.numberRow
        autocorrect = (try? c.decodeIfPresent(Bool.self, forKey: .autocorrect)) ?? d.autocorrect
        predictions = (try? c.decodeIfPresent(Bool.self, forKey: .predictions)) ?? d.predictions
        emojiPredictions = (try? c.decodeIfPresent(Bool.self, forKey: .emojiPredictions)) ?? d.emojiPredictions
        swipeTyping = (try? c.decodeIfPresent(Bool.self, forKey: .swipeTyping)) ?? d.swipeTyping
        autoCapitalization = (try? c.decodeIfPresent(Bool.self, forKey: .autoCapitalization)) ?? d.autoCapitalization
        doubleSpacePeriod = (try? c.decodeIfPresent(Bool.self, forKey: .doubleSpacePeriod)) ?? d.doubleSpacePeriod
        haptics = (try? c.decodeIfPresent(Bool.self, forKey: .haptics)) ?? d.haptics
        learnWords = (try? c.decodeIfPresent(Bool.self, forKey: .learnWords)) ?? d.learnWords
        height = (try? c.decodeIfPresent(Double.self, forKey: .height)) ?? d.height
        clipboardHistory = (try? c.decodeIfPresent(Bool.self, forKey: .clipboardHistory)) ?? d.clipboardHistory
        privateMode = (try? c.decodeIfPresent(Bool.self, forKey: .privateMode)) ?? d.privateMode
        clipboardDays = (try? c.decodeIfPresent(Int.self, forKey: .clipboardDays)) ?? d.clipboardDays
    }
}

/// A clipboard item. Pinned items are saved phrases: they never expire.
public struct SavedPhrase: Codable, Identifiable, Equatable {
    public var id: UUID
    public var text: String
    public var pinned: Bool
    public var createdAt: Date
    public var folder: String? = nil
    public init(text: String, pinned: Bool = false, createdAt: Date = Date()) {
        id = UUID(); self.text = String(text.prefix(ClipboardHistory.maxLength)); self.pinned = pinned; self.createdAt = createdAt
    }
}

/// Writing Assist actions: rewrites change the style, formats change the shape of the text.
/// The instructions are shared by Apple's on-device model and Backend/worker.mjs.
/// Which AI handles writing tools and translation.
public enum AIEngine: String, Codable, CaseIterable, Identifiable {
    case auto, service
    public var id: String { rawValue }
    public var title: String { self == .auto ? "Apple first, then WianTribe AI" : "WianTribe AI online" }
}

public enum WritingAction: String, Codable, CaseIterable, Identifiable {
    case grammar, professional, casual, polite, social, emojify, shorter, longer, summary, bullets, table, email, translate
    public var id: String { rawValue }
    public static let rewrites: [WritingAction] = [.grammar, .professional, .casual, .polite, .social, .emojify, .shorter, .longer]
    public static let formats: [WritingAction] = [.summary, .bullets, .table, .email]

    public var title: String {
        switch self {
        case .grammar: return "Fix grammar & spelling"
        case .professional: return "Professional"
        case .casual: return "Casual"
        case .polite: return "Polite"
        case .social: return "Social post"
        case .emojify: return "Add emoji"
        case .shorter: return "Shorter"
        case .longer: return "Longer"
        case .summary: return "Summarise"
        case .bullets: return "Bullet points"
        case .table: return "Table"
        case .email: return "Email"
        case .translate: return "Translate"
        }
    }

    public var instruction: String {
        switch self {
        case .grammar: return "Correct grammar, spelling and punctuation. Keep every sentence and line break, and keep the meaning, tone and language. Do not remove or summarise anything."
        case .professional: return "Rewrite in a clear, professional tone. Keep every point, the meaning and the language."
        case .casual: return "Rewrite in a friendly, casual tone. Keep every point, the meaning and the language."
        case .polite: return "Rewrite so it sounds polite, warm and respectful. Keep every point, the meaning and the language."
        case .social: return "Rewrite as an engaging social media post, ending with two to four relevant hashtags. Keep the language."
        case .emojify: return "Add a few fitting emoji to the text. Keep every word as it is."
        case .shorter: return "Make the text shorter and clearer, keeping the key points and the language."
        case .longer: return "Expand the text with a little more detail and smoother wording. Keep the meaning, tone and language. Do not invent facts."
        case .summary: return "Summarise the text in two or three sentences in the same language."
        case .bullets: return "Turn the text into a short list of key points, one per line, each starting with \"• \". Use the same language."
        case .table: return "Organise the information as a plain-text table: a header row, then one row per item, with columns separated by \" | \". Use the same language. Do not invent data; leave a cell empty if unknown."
        case .email: return "Format the text as a clear email: a greeting, short paragraphs and a closing line followed by [Your name]. Use the same language."
        case .translate: return "Translate the text into the requested language, preserving the meaning."
        }
    }

    /// Rewrites that must keep all of the person's text. A result that loses a large part of it is not offered.
    public var keepsAllText: Bool { [.grammar, .emojify, .professional, .casual, .polite].contains(self) }
}

/// Spots an AI result that left out part of the person's text, such as a dropped sentence,
/// so the keyboard never offers it as a replacement.
public enum WritingCheck {
    public struct LeftOutText: LocalizedError {
        public init() {}
        public var errorDescription: String? { "The AI left out part of your text. Try again, or select fewer lines." }
    }

    /// True when `result` has clearly fewer letters than `source`, for an action that must keep all the text.
    /// Spaces, punctuation and emoji don't count, and texts under 20 letters are not judged.
    public static func leftOutText(source: String, result: String, action: WritingAction) -> Bool {
        guard action.keepsAllText else { return false }
        let original = letters(in: source)
        guard original >= 20 else { return false }
        // Fixing grammar or adding emoji keeps nearly every letter; a change of tone may reword more.
        let minimum = action == .grammar || action == .emojify ? 0.75 : 0.4
        return Double(letters(in: result)) < Double(original) * minimum
    }

    static func letters(in text: String) -> Int {
        text.unicodeScalars.reduce(0) { $0 + (CharacterSet.letters.contains($1) ? 1 : 0) }
    }
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

    /// Stands in for "the start of a sentence" when learning which words a person begins with.
    public static let sentenceStart = "."
    /// Followers of one context are halved once a count passes this, so recent habits outweigh old ones.
    public static let recencyCeiling = 32
    public static let maxFollowers = 12

    /// The one or two words before the word being typed, for learning and predicting word patterns.
    /// `previous` is `sentenceStart` at the beginning of a sentence, and empty after other punctuation.
    public static func patternContext(in text: String) -> (previous: String, before: String) {
        let current = currentWord(in: text)
        let head = String(text.dropLast(current.count))
        let line = head.trimmingCharacters(in: .whitespaces)
        if line.isEmpty || line.hasSuffix("\n") { return (sentenceStart, "") }
        if let last = line.last, [".", "!", "?"].contains(String(last)) { return (sentenceStart, "") }
        let previous = currentWord(in: line)
        guard !previous.isEmpty else { return ("", "") }
        let earlier = String(line.dropLast(previous.count)).trimmingCharacters(in: .whitespaces)
        return (learningForm(previous.lowercased()), learningForm(currentWord(in: earlier).lowercased()))
    }

    /// The form a word is learned and looked up in: curly apostrophes made straight, and none at either
    /// end, so "don’t" and "don't" are one word and a word in 'quotes' is learned without them.
    public static func learningForm(_ word: String) -> String {
        var result = straightApostrophes(word)
        while result.hasPrefix("'") { result.removeFirst() }
        while result.hasSuffix("'") { result.removeLast() }
        return result.precomposedStringWithCanonicalMapping
    }

    public static func straightApostrophes(_ word: String) -> String {
        word.contains("’") ? word.replacingOccurrences(of: "’", with: "'") : word
    }

    /// Letters, with single apostrophes allowed between them: "don't", "c'est", "j'ai", "п'ять".
    static func isWordShape(_ word: String) -> Bool {
        guard let first = word.first, let last = word.last, first.isLetter, last.isLetter else { return false }
        var apostrophes = 0, afterApostrophe = false
        for character in word {
            if character == "'" || character == "’" {
                if afterApostrophe { return false }
                afterApostrophe = true; apostrophes += 1
            } else if character.isLetter {
                afterApostrophe = false
            } else { return false }
        }
        return apostrophes <= 2
    }

    /// Words that may serve as context for a prediction; unlike learned words this includes "a" and "i".
    public static func canBeContext(_ word: String) -> Bool {
        (1...24).contains(word.count) && isWordShape(word) && word == word.lowercased()
    }

    /// Words a language always writes with a capital letter wherever they fall, such as English "I" and "I'm".
    public static func properCase(_ word: String, language code: String) -> String {
        guard code == "en", word == "i" || word.hasPrefix("i'") || word.hasPrefix("i’") else { return word }
        return "I" + word.dropFirst()
    }

    /// Counts one more use of `word` after a context. A suggestion the person tapped counts double.
    public static func reinforced(_ followers: [String: Int], word: String, weight: Int = 1) -> [String: Int] {
        var next: [String: Int] = [:]
        for (key, value) in followers { next[key] = min(value, recencyCeiling) }
        let count = (next[word] ?? 0) + max(weight, 1)
        next[word] = count
        if count > recencyCeiling {
            var halved: [String: Int] = [:]
            for (key, value) in next where value / 2 > 0 { halved[key] = value / 2 }
            next = halved
        }
        while next.count > maxFollowers {
            var least: String?
            for (key, value) in next where key != word {
                if let current = least, let currentValue = next[current] {
                    if value < currentValue || (value == currentValue && key > current) { least = key }
                } else { least = key }
            }
            guard let least else { break }
            next.removeValue(forKey: least)
        }
        return next
    }

    /// Only words made of letters (and apostrophes inside them) are learned, never numbers, links or addresses.
    public static func canLearn(_ word: String) -> Bool {
        (2...24).contains(word.count) && isWordShape(word) && word == word.lowercased()
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
