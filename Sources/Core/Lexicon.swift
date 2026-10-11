import Foundation

/// A language's word list with frequencies, indexed by first letter for fast lookups.
public final class Lexicon {
    public let code: String
    public let words: [String]
    public let frequencies: [Int]
    private let index: [String: Int]
    private let byFirst: [Character: [Int]]

    public init(code: String, entries: [(String, Int)]) {
        self.code = code
        var words: [String] = [], frequencies: [Int] = [], index: [String: Int] = [:], byFirst: [Character: [Int]] = [:]
        words.reserveCapacity(entries.count); frequencies.reserveCapacity(entries.count)
        for (raw, frequency) in entries {
            let word = raw.precomposedStringWithCanonicalMapping
            guard !word.isEmpty, index[word] == nil else { continue }
            index[word] = words.count
            if let first = word.first { byFirst[first, default: []].append(words.count) }
            words.append(word); frequencies.append(frequency)
        }
        self.words = words; self.frequencies = frequencies; self.index = index; self.byFirst = byFirst
    }

    public var count: Int { words.count }
    public func frequency(of word: String) -> Int? { index[word.precomposedStringWithCanonicalMapping].map { frequencies[$0] } }
    public func contains(_ word: String) -> Bool { frequency(of: word) != nil }

    /// Word indexes beginning with any of these letters, most frequent first.
    public func indexes(startingWith letters: Set<Character>) -> [Int] {
        letters.flatMap { byFirst[$0] ?? [] }
    }

    /// The most common words, used as a fallback for next-word suggestions.
    public func top(_ count: Int, minimumLength: Int = 1) -> [String] {
        Array(words.lazy.filter { $0.count >= minimumLength }.prefix(count))
    }

    /// Parses the bundled "word<TAB>frequency" dictionary file for a language.
    public static func load(code: String, bundle: Bundle? = nil) -> Lexicon? {
        let bundle = bundle ?? LanguageCatalog.resourceBundle
        guard let url = bundle.url(forResource: "dict-\(code)", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        var entries: [(String, Int)] = []
        entries.reserveCapacity(30_000)
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let tab = line.firstIndex(of: "\t") else { continue }
            entries.append((String(line[..<tab]), Int(line[line.index(after: tab)...]) ?? 1))
        }
        return Lexicon(code: code, entries: entries)
    }
}

/// Keeps a few dictionaries in memory. Keyboard extensions have tight memory limits,
/// so the least recently used dictionary is released when more than `limit` are loaded.
public final class LexiconCache {
    public static let shared = LexiconCache()
    private let lock = NSLock()
    private var loaded: [String: Lexicon] = [:]
    private var order: [String] = []
    private var missing = Set<String>()
    public var limit = 4

    public func lexicon(for code: String, bundle: Bundle? = nil) -> Lexicon? {
        lock.lock(); defer { lock.unlock() }
        if let lexicon = loaded[code] { order.removeAll { $0 == code }; order.append(code); return lexicon }
        guard !missing.contains(code) else { return nil }
        guard let lexicon = Lexicon.load(code: code, bundle: bundle) else { missing.insert(code); return nil }
        loaded[code] = lexicon; order.append(code)
        while order.count > limit { loaded.removeValue(forKey: order.removeFirst()) }
        return lexicon
    }
}
