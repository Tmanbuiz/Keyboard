import Foundation

/// A language's word list with frequencies, indexed by first letter for fast lookups.
public final class Lexicon {
    public let code: String
    public let words: [String]
    public let frequencies: [Int]
    private let sortedIndexes: [UInt32]
    private let byFirst: [Character: [Int]]

    public init(code: String, entries: [(String, Int)]) {
        self.code = code
        var words: [String] = [], frequencies: [Int] = [], seen = Set<String>(), byFirst: [Character: [Int]] = [:]
        words.reserveCapacity(entries.count); frequencies.reserveCapacity(entries.count)
        for (raw, frequency) in entries {
            let word = raw.precomposedStringWithCanonicalMapping
            guard !word.isEmpty, seen.insert(word).inserted else { continue }
            if let first = word.first { byFirst[first, default: []].append(words.count) }
            words.append(word); frequencies.append(frequency)
        }
        self.words = words; self.frequencies = frequencies; self.byFirst = byFirst
        // Four bytes per word replace a resident String-to-Int hash table. Vocabulary is unchanged.
        self.sortedIndexes = words.indices.map(UInt32.init).sorted { words[Int($0)] < words[Int($1)] }
    }

    public var count: Int { words.count }
    public func frequency(of word: String) -> Int? {
        let target = word.precomposedStringWithCanonicalMapping
        var lower = 0, upper = sortedIndexes.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if words[Int(sortedIndexes[middle])] < target { lower = middle + 1 }
            else { upper = middle }
        }
        guard lower < sortedIndexes.count else { return nil }
        let index = Int(sortedIndexes[lower])
        return words[index] == target ? frequencies[index] : nil
    }
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
    private let loadingLock = NSLock()
    private var loaded: [String: Lexicon] = [:]
    private var order: [String] = []
    private var missing = Set<String>()
    private var cacheLimit = 3
    private var revision = 0
    public init() {}
    public var limit: Int {
        get { lock.lock(); defer { lock.unlock() }; return cacheLimit }
        set {
            lock.lock(); defer { lock.unlock() }
            cacheLimit = max(1, newValue)
            evict()
        }
    }
    private func evict() {
        while order.count > cacheLimit { loaded.removeValue(forKey: order.removeFirst()) }
    }
    /// Keep dictionaries used by the active engine; release only inactive cache entries.
    public func trim(keeping codes: Set<String>) {
        lock.lock(); defer { lock.unlock() }
        revision += 1
        for code in Array(loaded.keys) where !codes.contains(code) { loaded.removeValue(forKey: code) }
        order.removeAll { !codes.contains($0) }
    }
    public func lexicon(for code: String, bundle: Bundle? = nil) -> Lexicon? {
        lock.lock()
        if let lexicon = loaded[code] {
            order.removeAll { $0 == code }; order.append(code)
            lock.unlock(); return lexicon
        }
        let absent = missing.contains(code)
        lock.unlock()
        guard !absent else { return nil }
        // Serialize parsing to avoid duplicate allocations. Trimming never waits for file I/O.
        loadingLock.lock(); defer { loadingLock.unlock() }
        lock.lock()
        if let lexicon = loaded[code] {
            order.removeAll { $0 == code }; order.append(code)
            lock.unlock(); return lexicon
        }
        if missing.contains(code) { lock.unlock(); return nil }
        let requestedRevision = revision
        lock.unlock()
        let lexicon = Lexicon.load(code: code, bundle: bundle)
        lock.lock(); defer { lock.unlock() }
        guard let lexicon else { missing.insert(code); return nil }
        // Preserve the complete dictionary for the requester even if a memory warning trimmed the cache.
        if revision == requestedRevision {
            loaded[code] = lexicon; order.append(code); evict()
        }
        return lexicon
    }
}
