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
    private func storedData(_ key: String) -> Data? {
        reconcile(key)
        return (canWriteGroup ? data(key, in: group) : data(key, in: local)) ?? data(key, in: local) ?? data(key, in: group)
    }
    private func load<T: Decodable>(_ key: String, fallback: T) -> T {
        guard let data = storedData(key), let value = try? JSONDecoder().decode(T.self, from: data) else { return fallback }
        return value
    }
    /// Returns false when nothing was written.
    @discardableResult private func save<T: Encodable>(_ value: T, key: String) -> Bool {
        // Encoding first keeps the check for a clear made elsewhere right next to the write.
        guard let data = try? JSONEncoder().encode(value) else { return false }
        // A setter holding a pre-reset learning snapshot must not restore it.
        if reconcile(key), ["learned.v1", "pairs.v1"].contains(key) { return false }
        let now = Date()
        let current = generation(for: key)
        local.set(data, forKey: key); local.set(now, forKey: key + ".updatedAt"); local.set(current, forKey: key + ".generation")
        if canWriteGroup { group?.set(data, forKey: key); group?.set(now, forKey: key + ".updatedAt"); group?.set(current, forKey: key + ".generation") }
        return true
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
    // Settings are checked for every learned word, so they are decoded again only when the stored bytes change.
    private static let preferencesLock = NSLock()
    private static var preferencesCache: (data: Data, value: KeyboardPreferences)?
    var preferences: KeyboardPreferences {
        get {
            guard let data = storedData("preferences.v1") else { return KeyboardPreferences() }
            Self.preferencesLock.lock(); defer { Self.preferencesLock.unlock() }
            if let cached = Self.preferencesCache, cached.data == data { return cached.value }
            guard let value = try? JSONDecoder().decode(KeyboardPreferences.self, from: data) else { return KeyboardPreferences() }
            Self.preferencesCache = (data, value)
            return value
        }
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
    /// Normal OS teardown can also omit a dismissal callback. This is not a crash detector.
    var sessionOpen: Bool {
        get { local.bool(forKey: "session.open") }
        set { local.set(newValue, forKey: "session.open") }
    }
    /// Count only explicit memory-pressure callbacks from iOS.
    var memoryWarnings: Int {
        get { local.integer(forKey: "session.memoryWarnings") }
        set { local.set(newValue, forKey: "session.memoryWarnings") }
    }
    /// Which screen was open at each memory warning, and the least memory ever left before iOS's limit.
    /// Screen names and numbers only, kept on this device; never anything typed.
    var memoryWarningScreens: [String: Int] {
        get { (local.dictionary(forKey: "session.memoryWarningScreens") as? [String: Int]) ?? [:] }
        set { local.set(newValue, forKey: "session.memoryWarningScreens") }
    }
    var lowestMemoryHeadroomMB: Int? {
        get { local.object(forKey: "session.lowestHeadroomMB") as? Int }
        set { local.set(newValue, forKey: "session.lowestHeadroomMB") }
    }
    /// Where the memory went at the warning with the least left, such as "used 180 MB · dictionaries 6 MB". Numbers only.
    var lowestMemoryDetail: String? {
        get { local.string(forKey: "session.lowestDetail") }
        set { local.set(newValue, forKey: "session.lowestDetail") }
    }
    func recordMemoryWarning(screen: String, headroomMB: Int, detail: String = "") {
        var screens = memoryWarningScreens
        screens[screen, default: 0] += 1
        memoryWarningScreens = screens
        if headroomMB < (lowestMemoryHeadroomMB ?? Int.max) { lowestMemoryHeadroomMB = headroomMB; lowestMemoryDetail = detail }
    }
    func resetHealthCounters() {
        unexpectedCloses = 0; memoryWarnings = 0
        memoryWarningScreens = [:]; lowestMemoryHeadroomMB = nil; lowestMemoryDetail = nil
    }
    /// When the keyboard was last seen in use. Tells a restart while typing apart from iOS's routine
    /// clean-up of a keyboard left open in an app that went to the background.
    var sessionActiveAt: Date? {
        get { local.object(forKey: "session.activeAt") as? Date }
        set { local.set(newValue, forKey: "session.activeAt") }
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
    // The keyboard calls reloadLearning() whenever it appears, so changes made in the app (e.g. clearing) are picked up.
    private static var learnedCache: [String: Int]?
    private static var pairsCache: [String: [String: Int]]?
    /// Words learned while typing stay in memory until saveLearning(), so a space press never waits for storage.
    private static var unsavedLearning = false
    static var hasUnsavedLearning: Bool { unsavedLearning }
    /// Forgets the in-memory copy, including words not saved yet. Used after learned words are cleared.
    static func invalidateLearningCache() { learnedCache = nil; pairsCache = nil; unsavedLearning = false }
    /// Saves what was learned, then rereads storage so changes made in the app (clearing, iCloud) are picked up.
    func reloadLearning() { saveLearning(); Self.invalidateLearningCache() }
    /// Writes words learned in memory. The keyboard calls this when typing pauses and when it closes.
    func saveLearning() {
        guard Self.unsavedLearning else { return }
        Self.unsavedLearning = false
        let words = Self.learnedCache, pairs = Self.pairsCache
        if let words { learned = words }
        // If learned words were cleared elsewhere, the setter dropped the in-memory copy; the pairs are stale too.
        if let pairs, words == nil || Self.learnedCache != nil { learnedPairs = pairs }
    }
    var learned: [String: Int] {
        get {
            if let cached = Self.learnedCache { return cached }
            let value: [String: Int] = load("learned.v1", fallback: [String: Int]())
            Self.learnedCache = value; return value
        }
        set {
            Self.learnedCache = newValue
            // Refused when learned words were cleared elsewhere since they were read: drop the old copy too.
            if !save(newValue, key: "learned.v1") { Self.invalidateLearningCache() }
        }
    }
    /// Which word followed which, counted only when word learning is on. Used for next-word suggestions.
    var learnedPairs: [String: [String: Int]] {
        get {
            if let cached = Self.pairsCache { return cached }
            let value: [String: [String: Int]] = load("pairs.v1", fallback: [String: [String: Int]]())
            Self.pairsCache = value; return value
        }
        set {
            Self.pairsCache = newValue
            if !save(newValue, key: "pairs.v1") { Self.invalidateLearningCache() }
        }
    }
    /// Learns that `word` followed `previous`, and that it followed the two words `before previous`.
    /// `previous` may be `TextContext.sentenceStart`. Counts only; never the sentence itself.
    /// Kept in memory until saveLearning().
    func learnPair(previous: String, before: String = "", word: String, weight: Int = 1) {
        let word = TextContext.learningForm(word)
        let preferences = self.preferences
        guard preferences.learnWords, !preferences.privateMode, TextContext.canLearn(word) else { return }
        let previous = previous == TextContext.sentenceStart ? previous : TextContext.learningForm(previous)
        let before = TextContext.learningForm(before)
        var keys: [String] = []
        if previous == TextContext.sentenceStart { keys = [previous] }
        else if TextContext.canBeContext(previous) {
            keys = [previous]
            if TextContext.canBeContext(before) { keys.append(before + " " + previous) }
        }
        guard !keys.isEmpty else { return }
        var pairs = learnedPairs
        for key in keys { pairs[key] = TextContext.reinforced(pairs[key] ?? [:], word: word, weight: weight) }
        // Over the limit, forget the least used context rather than a random one.
        while pairs.count > BackupMerge.maxPairs {
            var least: String?, leastTotal = Int.max
            for (key, followers) in pairs where !keys.contains(key) {
                var total = 0
                for count in followers.values { total += count }
                if total < leastTotal { least = key; leastTotal = total }
            }
            guard let least else { break }
            pairs.removeValue(forKey: least)
        }
        Self.pairsCache = pairs; Self.unsavedLearning = true
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
    /// Counts one more use of a word the person typed. Kept in memory until saveLearning().
    func learn(_ word: String) {
        let word = TextContext.learningForm(word)
        let preferences = self.preferences
        guard preferences.learnWords, !preferences.privateMode, TextContext.canLearn(word) else { return }
        var words = learned
        words[word] = min((words[word] ?? 0) + 1, 500)
        if words.count > BackupMerge.maxLearned {
            // Make room by forgetting the least used word, never the one just typed.
            var least: String?, leastCount = Int.max
            for (key, count) in words where key != word && count < leastCount { least = key; leastCount = count }
            if let least { words.removeValue(forKey: least) }
        }
        Self.learnedCache = words; Self.unsavedLearning = true
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
    /// When learned words were last cleared on this device (by either clear button). iCloud backup
    /// uses it to carry the clear to the person's other devices.
    var learningResetAt: Date { resetDate(for: "learned.v1") }
    func clearLearnedWords() { reset("learning.resetAt", keys: ["learned.v1", "pairs.v1"]); Self.invalidateLearningCache() }
    func clearPersonalData() {
        // Keep IDs too, so an old UI snapshot cannot restore a clip with a future-dated timestamp.
        deletedClipIDs.formUnion(phrases.map(\.id))
        reset("personal.resetAt", keys: Self.historyKeys); Self.invalidateLearningCache()
    }
}
