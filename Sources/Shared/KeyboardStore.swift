import Foundation

// This build works without App Groups (important for sideloading/Personal Teams).
// A paid-team build can opt into the group via Configuration/Shared.entitlements.
final class KeyboardStore {
    static let appGroup = "group.com.wiantribe.keyboard"
    private let local = UserDefaults.standard
    private let group: UserDefaults?
    private let canWriteGroup: Bool
    var isShared: Bool { group != nil && canWriteGroup }

    init(canWriteGroup: Bool = true) {
        self.canWriteGroup = canWriteGroup
        if FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroup) != nil {
            group = UserDefaults(suiteName: Self.appGroup)
        } else { group = nil }
    }

    private func load<T: Decodable>(_ key: String, fallback: T) -> T {
        // Without Full Access, preferences changed inside the keyboard remain local.
        let data = (canWriteGroup ? group?.data(forKey: key) : local.data(forKey: key))
            ?? local.data(forKey: key) ?? group?.data(forKey: key)
        guard let data, let value = try? JSONDecoder().decode(T.self, from: data) else { return fallback }
        return value
    }
    private func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        local.set(data, forKey: key)
        if canWriteGroup { group?.set(data, forKey: key) }
    }
    var preferences: KeyboardPreferences {
        get { load("preferences.v1", fallback: KeyboardPreferences()) }
        set { save(newValue, key: "preferences.v1") }
    }
    /// Clipboard history and saved phrases (pinned items) in one list, newest first.
    var phrases: [SavedPhrase] {
        get {
            if let clips: [SavedPhrase] = load("clips.v2", fallback: nil) {
                return ClipboardHistory.pruned(clips, keepDays: preferences.clipboardDays)
            }
            // Phrases from v0.1 were saved on purpose, so they become pinned and never expire.
            let legacy: [SavedPhrase] = load("phrases.v1", fallback: [])
            return legacy.map { var item = $0; item.pinned = true; return item }
        }
        set { save(ClipboardHistory.pruned(newValue, keepDays: preferences.clipboardDays), key: "clips.v2") }
    }
    /// The pasteboard change count already looked at, so each copy is read at most once.
    var lastChangeCount: Int {
        get { local.object(forKey: "clipboard.changeCount") as? Int ?? -1 }
        set { local.set(newValue, forKey: "clipboard.changeCount") }
    }
    func capture(_ text: String) {
        phrases = ClipboardHistory.adding(text, to: phrases, keepDays: preferences.clipboardDays)
    }
    func clearRecentClips() { phrases = phrases.filter(\.pinned) }
    var learned: [String: Int] {
        get { load("learned.v1", fallback: [String: Int]()) }
        set { save(newValue, key: "learned.v1") }
    }
    /// Which word followed which, counted only when word learning is on. Used for next-word suggestions.
    var learnedPairs: [String: [String: Int]] {
        get { load("pairs.v1", fallback: [String: [String: Int]]()) }
        set { save(newValue, key: "pairs.v1") }
    }
    func learnPair(previous: String, word: String) {
        guard preferences.learnWords, TextContext.canLearn(previous), TextContext.canLearn(word) else { return }
        var pairs = learnedPairs
        var next = pairs[previous] ?? [:]
        next[word] = min((next[word] ?? 0) + 1, 500)
        if next.count > 12, let least = next.min(by: { $0.value < $1.value })?.key { next.removeValue(forKey: least) }
        pairs[previous] = next
        if pairs.count > 1500, let key = pairs.keys.first(where: { $0 != previous }) { pairs.removeValue(forKey: key) }
        learnedPairs = pairs
    }
    var recentEmoji: [String] {
        get { load("recentEmoji.v1", fallback: [String]()) }
        set { save(Array(newValue.prefix(40)), key: "recentEmoji.v1") }
    }
    func useEmoji(_ emoji: String) {
        var list = recentEmoji
        list.removeAll { $0 == emoji }
        list.insert(emoji, at: 0)
        recentEmoji = list
    }
    func learn(_ word: String) {
        guard preferences.learnWords, TextContext.canLearn(word) else { return }
        var words = learned
        words[word] = min((words[word] ?? 0) + 1, 500)
        if words.count > 1000, let least = words.min(by: { $0.value < $1.value })?.key { words.removeValue(forKey: least) }
        learned = words
    }
    func addPhrase(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        phrases = ClipboardHistory.adding(trimmed, to: phrases, pinned: true, keepDays: preferences.clipboardDays)
    }
    func clearPersonalData() {
        phrases = []; learned = [:]; learnedPairs = [:]
    }
}
