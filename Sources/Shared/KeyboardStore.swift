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

    private static let historyKeys = ["clips.v2", "phrases.v1", "learned.v1", "pairs.v1", "recentEmoji.v1"]
    private func resetDate(for key: String) -> Date {
        guard Self.historyKeys.contains(key) else { return .distantPast }
        let markers = ["personal.resetAt"] + (["learned.v1", "pairs.v1"].contains(key) ? ["learning.resetAt"] : [])
        return markers.flatMap { [local.object(forKey: $0) as? Date, group?.object(forKey: $0) as? Date] }.compactMap { $0 }.max() ?? .distantPast
    }
    private func generation(for key: String) -> String {
        let scopes = ["personal.resetAt"] + (["learned.v1", "pairs.v1"].contains(key) ? ["learning.resetAt"] : [])
        return scopes.map { scope in
            if local.bool(forKey: scope + ".pending") { return local.string(forKey: scope + ".generation") ?? "" }
            return group?.string(forKey: scope + ".generation") ?? local.string(forKey: scope + ".generation") ?? ""
        }.joined(separator: ":")
    }
    /// A read-only keyboard can hide shared history immediately, then publish its pending reset
    /// when Full Access returns. Timestamps prevent old local/group fallbacks from reviving it.
    @discardableResult private func reconcile(_ key: String) -> Bool {
        if canWriteGroup, let group {
            for marker in ["personal.resetAt", "learning.resetAt"] {
                if local.bool(forKey: marker + ".pending"), let pending = local.object(forKey: marker) as? Date {
                    group.set(pending, forKey: marker)
                    group.set(local.string(forKey: marker + ".generation"), forKey: marker + ".generation")
                    local.set(false, forKey: marker + ".pending")
                }
            }
        }
        let reset = resetDate(for: key)
        guard reset > .distantPast else { return false }
        let current = generation(for: key)
        let newlyObserved = reset > (local.object(forKey: key + ".resetSeen") as? Date ?? .distantPast) || current != (local.string(forKey: key + ".resetGenerationSeen") ?? "")
        if (local.object(forKey: key + ".updatedAt") as? Date ?? .distantPast) <= reset || (local.string(forKey: key + ".generation") ?? "") != current { local.removeObject(forKey: key) }
        if canWriteGroup, (group?.object(forKey: key + ".updatedAt") as? Date ?? .distantPast) <= reset || (group?.string(forKey: key + ".generation") ?? "") != current { group?.removeObject(forKey: key) }
        local.set(reset, forKey: key + ".resetSeen")
        local.set(current, forKey: key + ".resetGenerationSeen")
        return newlyObserved
    }
    private func data(_ key: String, in defaults: UserDefaults?) -> Data? {
        let reset = resetDate(for: key)
        guard reset == .distantPast || ((defaults?.object(forKey: key + ".updatedAt") as? Date ?? .distantPast) > reset &&
            (defaults?.string(forKey: key + ".generation") ?? "") == generation(for: key)) else { return nil }
        return defaults?.data(forKey: key)
    }
    private func load<T: Decodable>(_ key: String, fallback: T) -> T {
        reconcile(key)
        let data = (canWriteGroup ? data(key, in: group) : data(key, in: local)) ?? data(key, in: local) ?? data(key, in: group)
        guard let data, let value = try? JSONDecoder().decode(T.self, from: data) else { return fallback }
        return value
    }
    private func save<T: Encodable>(_ value: T, key: String) {
        // A setter holding a pre-reset learning snapshot must not restore it.
        if reconcile(key), ["learned.v1", "pairs.v1"].contains(key) { return }
        guard let data = try? JSONEncoder().encode(value) else { return }
        let now = Date()
        let current = generation(for: key)
        local.set(data, forKey: key); local.set(now, forKey: key + ".updatedAt"); local.set(current, forKey: key + ".generation")
        if canWriteGroup { group?.set(data, forKey: key); group?.set(now, forKey: key + ".updatedAt"); group?.set(current, forKey: key + ".generation") }
    }
    var writingRevokedAt: Date? {
        get {
            let dates = [group?.object(forKey: "writing.revokedAt") as? Date, local.object(forKey: "writing.revokedAt") as? Date]
            return dates.compactMap { $0 }.max()
        }
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
                var list = clips.filter { !deletedClipIDs.contains($0.id) }
                // Without Full Access the keyboard keeps its own list, but it can still read items saved
                // by the app, the Share menu or the Shortcut into the App Group, so merge them in.
                if !canWriteGroup, let data = data("clips.v2", in: group),
                   let shared = try? JSONDecoder().decode([SavedPhrase].self, from: data) {
                    let known = Set(list.map(\.text))
                    list = (list + shared.filter { !known.contains($0.text) }).sorted { $0.createdAt > $1.createdAt }
                }
                return ClipboardHistory.pruned(list.filter { !deletedClipIDs.contains($0.id) && $0.createdAt > resetDate(for: "clips.v2") }, keepDays: preferences.clipboardDays)
            }
            // Phrases from v0.1 were saved on purpose, so they become pinned and never expire.
            let legacy: [SavedPhrase] = load("phrases.v1", fallback: [])
            return legacy.filter { $0.createdAt > resetDate(for: "phrases.v1") }.map { var item = $0; item.pinned = true; return item }
        }
        set {
            let remaining = Set(newValue.map(\.id))
            deletedClipIDs.formUnion(phrases.filter { !remaining.contains($0.id) }.map(\.id))
            save(ClipboardHistory.pruned(newValue.filter { $0.createdAt > resetDate(for: "clips.v2") && !deletedClipIDs.contains($0.id) }, keepDays: preferences.clipboardDays), key: "clips.v2")
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
    // Decoding these from UserDefaults on every key press made typing lag, so each process keeps an in-memory copy.
    // The keyboard calls invalidateLearningCache() whenever it appears, so changes made in the app (e.g. clearing) are picked up.
    private static var learnedCache: [String: Int]?
    private static var pairsCache: [String: [String: Int]]?
    static func invalidateLearningCache() { learnedCache = nil; pairsCache = nil }
    var learned: [String: Int] {
        get {
            if let cached = Self.learnedCache { return cached }
            let value: [String: Int] = load("learned.v1", fallback: [String: Int]())
            Self.learnedCache = value; return value
        }
        set { Self.learnedCache = newValue; save(newValue, key: "learned.v1") }
    }
    /// Which word followed which, counted only when word learning is on. Used for next-word suggestions.
    var learnedPairs: [String: [String: Int]] {
        get {
            if let cached = Self.pairsCache { return cached }
            let value: [String: [String: Int]] = load("pairs.v1", fallback: [String: [String: Int]]())
            Self.pairsCache = value; return value
        }
        set { Self.pairsCache = newValue; save(newValue, key: "pairs.v1") }
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
    private func reset(_ marker: String, keys: [String]) {
        let now = Date()
        let id = UUID().uuidString
        local.set(now, forKey: marker); local.set(id, forKey: marker + ".generation")
        local.set(group != nil && !canWriteGroup, forKey: marker + ".pending")
        if canWriteGroup { group?.set(now, forKey: marker); group?.set(id, forKey: marker + ".generation") }
        for key in keys {
            local.removeObject(forKey: key)
            local.set(now, forKey: key + ".resetSeen")
            local.set(generation(for: key), forKey: key + ".resetGenerationSeen")
            if canWriteGroup { group?.removeObject(forKey: key) }
        }
    }
    func clearLearnedWords() { reset("learning.resetAt", keys: ["learned.v1", "pairs.v1"]); Self.invalidateLearningCache() }
    func clearPersonalData() {
        // Keep IDs too, so an old UI snapshot cannot restore a clip with a future-dated timestamp.
        deletedClipIDs.formUnion(phrases.map(\.id))
        reset("personal.resetAt", keys: Self.historyKeys); Self.invalidateLearningCache()
    }
}
