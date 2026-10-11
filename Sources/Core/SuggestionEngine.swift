import Foundation

public struct LexiconEntry: Codable, Equatable {
    public let word: String
    public let frequency: Int
    public let language: KeyboardLanguage
    public init(word: String, frequency: Int, language: KeyboardLanguage = .english) {
        self.word = word; self.frequency = frequency; self.language = language
    }
}

public struct WordSuggestion: Equatable {
    public let text: String
    public let score: Double
    public let isCorrection: Bool
}

public struct SuggestionEngine {
    public let entries: [LexiconEntry]
    private let known: Set<String>
    private let frequencies: [String: Int]

    public init(entries: [LexiconEntry]) {
        self.entries = entries
        known = Set(entries.map { $0.word.lowercased() })
        frequencies = Dictionary(entries.map { ($0.word.lowercased(), $0.frequency) }, uniquingKeysWith: max)
    }

    public static func bundled(bundle: Bundle? = nil) -> SuggestionEngine {
        #if SWIFT_PACKAGE
        let resourceBundle = bundle ?? Bundle.module
        #else
        let resourceBundle = bundle ?? Bundle.main
        #endif
        guard let url = resourceBundle.url(forResource: "Lexicon", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([LexiconEntry].self, from: data) else {
            return SuggestionEngine(entries: [])
        }
        return SuggestionEngine(entries: entries)
    }

    public func contains(_ word: String) -> Bool { known.contains(word.lowercased()) }
    public func frequency(of word: String) -> Int { frequencies[word.lowercased()] ?? 1 }

    public func suggestions(for original: String, previous: String = "", language: KeyboardLanguage,
                            learned: [String: Int] = [:], supplemental: [String] = [], limit: Int = 3) -> [WordSuggestion] {
        let word = original.lowercased().precomposedStringWithCanonicalMapping
        if word.isEmpty {
            let next = nextWords(after: previous, language: language)
            return Array(next.prefix(limit)).map { WordSuggestion(text: $0, score: 1, isCorrection: false) }
        }
        guard word.count <= 32 else { return [] }
        var results: [String: WordSuggestion] = [:]
        let candidates = entries.filter { $0.language == language || (language == .pidgin && $0.language == .english) }
        func consider(_ candidate: String, frequency: Int, personal: Bool = false) {
            let normalized = candidate.lowercased().precomposedStringWithCanonicalMapping
            guard normalized != word else { return }
            let prefix = normalized.hasPrefix(word)
            guard prefix || abs(normalized.count - word.count) <= 2 else { return }
            let distance = prefix ? 0 : (Self.isTransposition(word, normalized) ? 1 : Self.editDistance(word, normalized))
            guard prefix || distance <= (word.count > 6 ? 2 : 1) || Self.isTransposition(word, normalized) else { return }
            let score = (prefix ? 6.0 : 3.0 - Double(distance)) + log(Double(max(frequency, 1)) + 1) / 3
                + (personal ? 1 : 0) + (nextWords(after: previous, language: language).contains(normalized) ? 2 : 0)
            let result = WordSuggestion(text: TextContext.matchingCase(candidate, to: original), score: score, isCorrection: !prefix)
            if results[normalized] == nil || results[normalized]!.score < score { results[normalized] = result }
        }
        for entry in candidates { consider(entry.word, frequency: entry.frequency) }
        for (candidate, count) in learned { consider(candidate, frequency: min(count * 20, 1000), personal: true) }
        for candidate in supplemental where candidate.count <= 32 { consider(candidate, frequency: frequencies[candidate.lowercased()] ?? 10) }
        return Array(results.values.sorted { $0.score == $1.score ? $0.text < $1.text : $0.score > $1.score }.prefix(limit))
    }

    public func autocorrection(for word: String, language: KeyboardLanguage, protectedWords: Set<String> = [],
                               supplemental: [String] = []) -> String? {
        // Dialect/diacritics, names, acronyms, apostrophes and short words are never silently changed.
        guard language == .english, (3...24).contains(word.count), word == word.lowercased(),
              word.unicodeScalars.allSatisfy({ (97...122).contains(Int($0.value)) }),
              !known.contains(word), !protectedWords.contains(word) else { return nil }
        let shortlist = suggestions(for: word, language: language, supplemental: supplemental, limit: 12)
            .filter { $0.isCorrection && (Self.isTransposition(word, $0.text) || Self.editDistance(word, $0.text) == 1) }
        guard let first = shortlist.first, frequency(of: first.text) >= 30,
              shortlist.count == 1 || first.score - shortlist[1].score > 0.35 else { return nil }
        return first.text
    }

    public static func editDistance(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs), b = Array(rhs)
        var previous = Array(0...b.count)
        for (i, character) in a.enumerated() {
            var current = [i + 1]
            for (j, other) in b.enumerated() {
                current.append(min(current[j] + 1, previous[j + 1] + 1, previous[j] + (character == other ? 0 : 1)))
            }
            previous = current
        }
        return previous[b.count]
    }

    public static func isTransposition(_ lhs: String, _ rhs: String) -> Bool {
        let a = Array(lhs), b = Array(rhs)
        guard a.count == b.count else { return false }
        let different = a.indices.filter { a[$0] != b[$0] }
        return different.count == 2 && different[1] == different[0] + 1
            && a[different[0]] == b[different[1]] && a[different[1]] == b[different[0]]
    }

    public func nextWords(after word: String, language: KeyboardLanguage) -> [String] {
        if language == .yoruba { return ["ẹ", "ni", "àti"] }
        if language == .pidgin { return word.lowercased() == "how" ? ["far", "you", "e"] : ["you", "dey", "na"] }
        let pairs = ["thank": ["you", "you!", "goodness"], "how": ["are", "do", "is"],
                     "good": ["morning", "night", "luck"], "i": ["am", "will", "have"],
                     "see": ["you", "it", "the"], "hello": ["there", "world", "everyone"]]
        return pairs[word.lowercased()] ?? ["I", "the", "you"]
    }
}
