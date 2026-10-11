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
    var phrases: [SavedPhrase] {
        get { load("phrases.v1", fallback: [SavedPhrase]()) }
        set { save(Array(newValue.prefix(50)), key: "phrases.v1") }
    }
    var learned: [String: Int] {
        get { load("learned.v1", fallback: [String: Int]()) }
        set { save(newValue, key: "learned.v1") }
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
        guard !trimmed.isEmpty else { return }
        var items = phrases
        items.removeAll { $0.text == String(trimmed.prefix(2000)) }
        items.insert(SavedPhrase(text: trimmed), at: 0)
        phrases = items
    }
    func clearPersonalData() {
        phrases = []; learned = [:]
    }
}
