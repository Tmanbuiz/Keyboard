import Foundation

// This build works without App Groups (important for sideloading/Personal Teams).
// A paid-team build can opt into the group via Configuration/Shared.entitlements.
final class KeyboardStore {
    static var appGroup: String {
        #if PERSONAL_BACKGROUND_CLIPBOARD
        // Clipper uses ALTAppGroups so SideStore/AltStore can remap the group
        // consistently when re-signing the app and all its extensions.
        return (Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String])?.first
            ?? "group.com.wiantribe.keyboard.personal"
        #else
        return "group.com.wiantribe.keyboard"
        #endif
    }
    private let local = UserDefaults.standard
    private let group: UserDefaults?
    private let canWriteGroup: Bool
    #if PERSONAL_BACKGROUND_CLIPBOARD
    private let personalArchive: ClipboardArchive?
    #endif
    var isShared: Bool { group != nil && canWriteGroup }
    /// True when the App Group exists (App Store and paid-team builds), even if this process can't write to it.
    var hasGroup: Bool { group != nil }

    init(canWriteGroup: Bool = true) {
        self.canWriteGroup = canWriteGroup
        if FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroup) != nil {
            group = UserDefaults(suiteName: Self.appGroup)
        } else { group = nil }
        #if PERSONAL_BACKGROUND_CLIPBOARD
        if let folder = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroup) {
            let old = group?.data(forKey: "clips.v2").flatMap { try? JSONDecoder().decode([SavedPhrase].self, from: $0) } ?? []
            personalArchive = ClipboardArchive(url: folder.appendingPathComponent("personal-clips-v1.json"), initial: old)
        } else { personalArchive = nil }
        #endif
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
            #if PERSONAL_BACKGROUND_CLIPBOARD
            if let archive = personalArchive, let shared = try? archive.read() {
                if canWriteGroup { return ClipboardHistory.pruned(shared, keepDays: preferences.clipboardDays) }
                let mine: [SavedPhrase] = load("clips.v2", fallback: [])
                let known = Set(mine.map(\.text))
                return ClipboardHistory.pruned((mine + shared.filter { !known.contains($0.text) })
                    .sorted { $0.createdAt > $1.createdAt }, keepDays: preferences.clipboardDays)
            }
            #endif
            if let clips: [SavedPhrase] = load("clips.v2", fallback: nil) {
                var list = clips
                // Without Full Access the keyboard keeps its own list, but it can still read items saved
                // by the app, the Share menu or the Shortcut into the App Group, so merge them in.
                if !canWriteGroup, let data = group?.data(forKey: "clips.v2"),
                   let shared = try? JSONDecoder().decode([SavedPhrase].self, from: data) {
                    let known = Set(list.map(\.text))
                    list = (list + shared.filter { !known.contains($0.text) }).sorted { $0.createdAt > $1.createdAt }
                }
                return ClipboardHistory.pruned(list, keepDays: preferences.clipboardDays)
            }
            // Phrases from v0.1 were saved on purpose, so they become pinned and never expire.
            let legacy: [SavedPhrase] = load("phrases.v1", fallback: [])
            return legacy.map { var item = $0; item.pinned = true; return item }
        }
        set {
            let value = ClipboardHistory.pruned(newValue, keepDays: preferences.clipboardDays)
            #if PERSONAL_BACKGROUND_CLIPBOARD
            if canWriteGroup, let archive = personalArchive {
                _ = try? archive.update { _ in value }
                return
            }
            #endif
            save(value, key: "clips.v2")
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
        #if PERSONAL_BACKGROUND_CLIPBOARD
        if canWriteGroup, let archive = personalArchive {
            _ = try? archive.update { ClipboardHistory.adding(text, to: $0, keepDays: self.preferences.clipboardDays) }
            return
        }
        #endif
        phrases = ClipboardHistory.adding(text, to: phrases, keepDays: preferences.clipboardDays)
    }
    #if PERSONAL_BACKGROUND_CLIPBOARD
    func captureFromNotification(_ text: String) throws {
        guard canWriteGroup, let archive = personalArchive else { throw PersonalClipboardError.missingSharedStorage }
        try archive.update { ClipboardHistory.adding(text, to: $0, keepDays: self.preferences.clipboardDays) }
    }
    #endif
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
