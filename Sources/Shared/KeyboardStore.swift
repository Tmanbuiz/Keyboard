import Foundation
#if SWIFT_PACKAGE
import TypingCore
#endif

// This build works without App Groups (important for sideloading/Personal Teams).
// A paid-team build can opt into the group via Configuration/Shared.entitlements.
final class KeyboardStore {
    static let appGroup = "group.com.wiantribe.keyboard"
    private let local: UserDefaults
    private let group: UserDefaults?
    private let canWriteGroup: Bool
    var isShared: Bool { group != nil && canWriteGroup }
    /// True when the App Group exists (App Store and paid-team builds), even if this process can't write to it.
    var hasGroup: Bool { group != nil }

    init(canWriteGroup: Bool = true) {
        self.local = .standard
        self.canWriteGroup = canWriteGroup
        if FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroup) != nil {
            group = UserDefaults(suiteName: Self.appGroup)
        } else { group = nil }
    }

    // Dependency injection lets storage behaviour be tested with isolated defaults suites.
    init(local: UserDefaults, group: UserDefaults?, canWriteGroup: Bool) {
        self.local = local; self.group = group; self.canWriteGroup = canWriteGroup
    }

    private func synchronizeReset() {
        guard let reset = group?.object(forKey: "personal.resetAt") as? Date,
              reset > (local.object(forKey: "personal.resetSeen") as? Date ?? .distantPast) else { return }
        for key in ["clips.v2", "phrases.v1", "learned.v1", "pairs.v1", "recentEmoji.v1"] { local.removeObject(forKey: key) }
        local.set(reset, forKey: "personal.resetSeen")
    }
    private func load<T: Decodable>(_ key: String, fallback: T) -> T {
        synchronizeReset()
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
    var writingRevokedAt: Date? {
        get { group?.object(forKey: "writing.revokedAt") as? Date ?? local.object(forKey: "writing.revokedAt") as? Date }
        set {
            local.set(newValue, forKey: "writing.revokedAt")
            if canWriteGroup { group?.set(newValue, forKey: "writing.revokedAt") }
        }
    }
    private var deletedClipIDs: Set<UUID> {
        get {
            let own = (local.stringArray(forKey: "clips.deleted") ?? []).compactMap(UUID.init(uuidString:))
            let shared = (group?.stringArray(forKey: "clips.deleted") ?? []).compactMap(UUID.init(uuidString:))
            return Set(own + shared)
        }
        set {
            let values = newValue.map(\.uuidString)
            local.set(values, forKey: "clips.deleted")
            if canWriteGroup { group?.set(values, forKey: "clips.deleted") }
        }
    }
    var preferences: KeyboardPreferences {
        get { load("preferences.v1", fallback: KeyboardPreferences()) }
        set { save(newValue, key: "preferences.v1") }
    }
    /// Clipboard history and saved phrases (pinned items) in one list, newest first.
    var phrases: [SavedPhrase] {
        get {
            if let clips: [SavedPhrase] = load("clips.v2", fallback: nil) {
                var list = clips
                // Without Full Access the keyboard keeps its own list, but it can still read items saved
                // by the app, the Share menu or the Shortcut into the App Group, so merge them in.
                if !canWriteGroup, let data = group?.data(forKey: "clips.v2"),
                   let shared = try? JSONDecoder().decode([SavedPhrase].self, from: data) {
                    let known = Set(list.map(\.text))
                    list = (list + shared.filter { !known.contains($0.text) }).sorted { $0.createdAt > $1.createdAt }
                }
                return ClipboardHistory.pruned(list.filter { !deletedClipIDs.contains($0.id) }, keepDays: preferences.clipboardDays)
            }
            // Phrases from v0.1 were saved on purpose, so they become pinned and never expire.
            let legacy: [SavedPhrase] = load("phrases.v1", fallback: [])
            return legacy.map { var item = $0; item.pinned = true; return item }
        }
        set {
            let remaining = Set(newValue.map(\.id))
            deletedClipIDs.formUnion(phrases.filter { !remaining.contains($0.id) }.map(\.id))
            save(ClipboardHistory.pruned(newValue, keepDays: preferences.clipboardDays), key: "clips.v2")
        }
    }
    /// The pasteboard change count already looked at, so each copy is read at most once.
    var lastChangeCount: Int {
        get { local.object(forKey: "clipboard.changeCount") as? Int ?? -1 }
        set { local.set(newValue, forKey: "clipboard.changeCount") }
    }
    /// True while the keyboard is on screen. If it is still true when the keyboard next starts,
    /// iOS ended the last session abnormally (a crash or the memory limit) and showed Apple's keyboard.
    var sessionOpen: Bool {
        get { local.bool(forKey: "session.open") }
        set { local.set(newValue, forKey: "session.open") }
    }
    var unexpectedCloses: Int {
        get { local.integer(forKey: "session.unexpectedCloses") }
        set { local.set(newValue, forKey: "session.unexpectedCloses") }
    }
    /// Set after the first copy is read successfully, so setup help can be hidden from then on.
    var clipboardWorked: Bool {
        get { local.bool(forKey: "clipboard.worked") }
        set { local.set(newValue, forKey: "clipboard.worked") }
    }
    func capture(_ text: String) {
        guard !preferences.privateMode else { return }
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
        guard preferences.learnWords, !preferences.privateMode, TextContext.canLearn(previous), TextContext.canLearn(word) else { return }
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
        guard preferences.learnWords, !preferences.privateMode, TextContext.canLearn(word) else { return }
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
        phrases = []; learned = [:]; learnedPairs = [:]; recentEmoji = []
        local.removeObject(forKey: "phrases.v1")
        if canWriteGroup {
            group?.removeObject(forKey: "phrases.v1")
            let reset = Date()
            group?.set(reset, forKey: "personal.resetAt")
            local.set(reset, forKey: "personal.resetSeen")
        }
    }
}
