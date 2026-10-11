import Foundation

public struct WordSuggestion: Equatable {
    public let text: String
    public let score: Double
    public let isCorrection: Bool
    public let language: String
}

/// Completions, corrections and next-word predictions across one or more languages.
/// The first lexicon belongs to the language on screen; the others come from multilingual typing.
public struct SuggestionEngine {
    public let language: LanguagePack
    public let lexicons: [Lexicon]

    public init(language: LanguagePack, lexicons: [Lexicon]) {
        self.language = language; self.lexicons = lexicons
    }

    /// Loads dictionaries for the current language plus, when multilingual, others written in the same script.
    public static func make(primary: KeyboardLanguage, others: [KeyboardLanguage] = [], cache: LexiconCache = .shared) -> SuggestionEngine {
        let pack = primary.pack
        let script = Set(pack.rows.joined())
        var lexicons: [Lexicon] = []
        if let main = cache.lexicon(for: pack.code) { lexicons.append(main) }
        for other in others where other != primary {
            // Mixing scripts never helps a single word, so only same-alphabet languages are combined.
            guard !Set(other.pack.rows.joined()).isDisjoint(with: script), let lexicon = cache.lexicon(for: other.code) else { continue }
            lexicons.append(lexicon)
        }
        return SuggestionEngine(language: pack, lexicons: lexicons)
    }

    public var primary: Lexicon? { lexicons.first { $0.code == language.code } }
    public func contains(_ word: String) -> Bool { lexicons.contains { $0.contains(normalize(word)) } }
    public func frequency(of word: String) -> Int? { lexicons.compactMap { $0.frequency(of: normalize(word)) }.max() }

    func normalize(_ word: String) -> String { language.lowercased(word).precomposedStringWithCanonicalMapping }

    public func suggestions(for original: String, previous: String = "", learned: [String: Int] = [:],
                            learnedPairs: [String: [String: Int]] = [:], supplemental: [String] = [], limit: Int = 3) -> [WordSuggestion] {
        let word = normalize(original)
        if word.isEmpty {
            return Array(nextWords(after: previous, learnedPairs: learnedPairs).prefix(limit))
                .map { WordSuggestion(text: $0, score: 1, isCorrection: false, language: language.code) }
        }
        guard word.count <= 32 else { return [] }
        let likely = Set(nextWords(after: previous, learnedPairs: learnedPairs))
        let active = activeLanguage(previous: previous)
        var results: [String: WordSuggestion] = [:]
        let first = word.first!
        let starts: Set<Character> = word.count > 2 ? [first, Array(word)[1]] : [first]

        func consider(_ candidate: String, frequency: Int, code: String, personal: Bool = false) {
            let normalized = normalize(candidate)
            guard normalized != word else { return }
            let prefix = normalized.hasPrefix(word)
            guard prefix || abs(normalized.count - word.count) <= 2 else { return }
            let transposed = Self.isTransposition(word, normalized)
            let distance = prefix ? 0 : (transposed ? 1 : Self.editDistance(word, normalized, limit: 2))
            guard prefix || distance <= (word.count > 6 ? 2 : 1) else { return }
            let score = (prefix ? 6.0 : 3.0 - Double(distance)) + log(Double(max(frequency, 1)) + 1) / 3
                + (personal ? 1 : 0) + (likely.contains(normalized) ? 2 : 0) + (code == active ? 0.6 : 0)
            let text = TextContext.matchingCase(candidate, to: original, language: language)
            let result = WordSuggestion(text: text, score: score, isCorrection: !prefix, language: code)
            if results[normalized] == nil || results[normalized]!.score < score { results[normalized] = result }
        }
        for lexicon in lexicons {
            for i in lexicon.indexes(startingWith: starts) { consider(lexicon.words[i], frequency: lexicon.frequencies[i], code: lexicon.code) }
        }
        for (candidate, count) in learned { consider(candidate, frequency: min(count * 20, 1000), code: language.code, personal: true) }
        for candidate in supplemental where candidate.count <= 32 {
            consider(candidate, frequency: frequency(of: candidate) ?? 10, code: language.code)
        }
        return Array(results.values.sorted { $0.score == $1.score ? $0.text < $1.text : $0.score > $1.score }.prefix(limit))
    }

    /// The language the person seems to be writing in right now, judged by the previous word.
    func activeLanguage(previous: String) -> String {
        let word = normalize(previous)
        guard !word.isEmpty, lexicons.count > 1 else { return language.code }
        if primary?.contains(word) == true { return language.code }
        return lexicons.first { $0.contains(word) }?.code ?? language.code
    }

    /// A confident single-edit fix for an unknown word, or nil. Words known in any enabled language,
    /// names, acronyms, words with digits and dialect languages are never silently changed.
    public func autocorrection(for word: String, protectedWords: Set<String> = [], supplemental: [String] = []) -> String? {
        guard language.autocorrect, let primary, (3...24).contains(word.count), word == language.lowercased(word),
              word.allSatisfy({ $0.isLetter || $0 == "'" }), !protectedWords.contains(word) else { return nil }
        let own = frequency(of: word)
        if let own, own >= 20 { return nil } // A real word in one of the person's languages.
        let shortlist = suggestions(for: word, supplemental: supplemental, limit: 12)
            .filter { $0.isCorrection && $0.language == primary.code
                && (Self.isTransposition(word, normalize($0.text)) || Self.editDistance(word, normalize($0.text), limit: 1) == 1) }
        guard let best = shortlist.first, let bestFrequency = frequency(of: best.text),
              bestFrequency >= 30, bestFrequency >= (own ?? 0) * 40,
              shortlist.count == 1 || best.score - shortlist[1].score > 0.35 else { return nil }
        return best.text
    }

    /// Words likely to follow `word`: the person's own pairs first, then built-in pairs, then common words.
    public func nextWords(after word: String, learnedPairs: [String: [String: Int]] = [:]) -> [String] {
        let key = normalize(word)
        var result: [String] = []
        func add(_ items: [String]) { for item in items where !result.contains(item) { result.append(item) } }
        if let personal = learnedPairs[key] { add(personal.sorted { $0.value > $1.value }.map(\.key)) }
        add(language.nextWords[key] ?? [])
        if result.count < 3 {
            if key.isEmpty, let primary { add(primary.top(3, minimumLength: language.code == "en" ? 1 : 2)) }
            else if let primary { add(primary.top(3, minimumLength: 2)) }
        }
        return Array(result.prefix(3))
    }

    /// Words a glide can produce, limited to those starting near where the finger went down.
    public func glideWords(startingWith letters: Set<Character>) -> [(String, Int)] {
        var seen = Set<String>(), result: [(String, Int)] = []
        for lexicon in lexicons {
            for i in lexicon.indexes(startingWith: letters) where seen.insert(lexicon.words[i]).inserted {
                result.append((lexicon.words[i], lexicon.frequencies[i]))
            }
        }
        return result
    }

    /// Levenshtein distance that gives up early once it exceeds `limit`.
    public static func editDistance(_ lhs: String, _ rhs: String, limit: Int = .max) -> Int {
        let a = Array(lhs), b = Array(rhs)
        if abs(a.count - b.count) > limit { return limit + 1 }
        var previous = Array(0...b.count)
        for (i, character) in a.enumerated() {
            var current = [i + 1]
            var best = i + 1
            for (j, other) in b.enumerated() {
                let value = min(current[j] + 1, previous[j + 1] + 1, previous[j] + (character == other ? 0 : 1))
                current.append(value); best = min(best, value)
            }
            if best > limit { return limit + 1 }
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
}
