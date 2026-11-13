import Foundation

/// Optional backup of learned words, pinned text, recent emoji and settings to the person's own iCloud
/// (Apple's key-value storage). Off until switched on. WianTribe never receives this data, and recent
/// clipboard items are never included. It runs in the app only; the keyboard has no part in it.
@MainActor
final class CloudBackup: ObservableObject {
    static let shared = CloudBackup()
    /// Posted after a sync changed what is stored on this device, so screens can reload.
    static let didApply = Notification.Name("WianTribeCloudBackupDidApply")

    private static let cloudKey = "backup.v1"
    private static let enabledKey = "cloudBackup.enabled"
    private static let baseKey = "cloudBackup.base"
    private static let epochKey = "cloudBackup.epoch"
    private static let seenResetKey = "cloudBackup.seenResetAt"
    /// iCloud key-value storage allows 1 MB in total; stay well inside it.
    private static let maxBytes = 900_000

    private let cloud = NSUbiquitousKeyValueStore.default
    private let defaults = UserDefaults.standard
    private let store = KeyboardStore()
    private var observer: NSObjectProtocol?

    @Published private(set) var status = ""
    @Published var enabled: Bool {
        didSet {
            guard enabled != oldValue else { return }
            defaults.set(enabled, forKey: Self.enabledKey)
            if enabled { sync() } else { status = "" }
        }
    }

    private init() {
        enabled = defaults.bool(forKey: Self.enabledKey)
        observer = NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                                                          object: cloud, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.sync() }
        }
    }

    /// Merges this device with the iCloud copy and saves the result to both. Does nothing while backup is off.
    func sync() {
        guard enabled else { return }
        guard FileManager.default.ubiquityIdentityToken != nil else {
            status = String(localized: "Sign in to iCloud in the Settings app to use backup."); return
        }
        cloud.synchronize()
        var remote: BackupPayload?
        if let data = cloud.data(forKey: Self.cloudKey) {
            guard let decoded = Self.decode(data), decoded.version == 1 else {
                // Written by a newer version of the app, or unreadable. Never overwrite it blindly.
                status = String(localized: "The iCloud backup can't be read by this version. Update WianTribe, or delete the backup to start again."); return
            }
            remote = decoded
        }
        let base = defaults.data(forKey: Self.baseKey).flatMap(Self.decode)
        // The keyboard may have learned words since the app last looked.
        KeyboardStore.invalidateLearningCache()
        let local = BackupPayload(learningEpoch: defaults.string(forKey: Self.epochKey) ?? "",
                                  learned: store.learned, pairs: store.learnedPairs,
                                  pinned: store.phrases.filter(\.pinned), emoji: store.recentEmoji,
                                  preferences: store.preferences)
        let seenReset = defaults.object(forKey: Self.seenResetKey) as? Date ?? .distantPast
        let result = BackupMerge.merge(base: base, local: local, remote: remote,
                                       locallyCleared: store.learningResetAt > seenReset, newEpoch: UUID().uuidString)
        guard let data = Self.encode(result.payload), data.count <= Self.maxBytes, let saved = Self.decode(data) else {
            status = String(localized: "Backup is too large for iCloud. Remove some pinned text and try again."); return
        }
        let changedHere = apply(result, local: local)
        if remote != saved { cloud.set(data, forKey: Self.cloudKey); cloud.synchronize() }
        defaults.set(data, forKey: Self.baseKey)
        defaults.set(saved.learningEpoch, forKey: Self.epochKey)
        defaults.set(store.learningResetAt, forKey: Self.seenResetKey)
        status = String(localized: "Backed up to iCloud") + " · " + Date().formatted(date: .abbreviated, time: .shortened)
        if changedHere { NotificationCenter.default.post(name: Self.didApply, object: nil) }
    }

    /// Removes the iCloud copy and turns backup off. Everything on this device is kept.
    func deleteBackup() {
        cloud.removeObject(forKey: Self.cloudKey); cloud.synchronize()
        for key in [Self.baseKey, Self.epochKey, Self.seenResetKey] { defaults.removeObject(forKey: key) }
        enabled = false
        status = String(localized: "iCloud backup deleted. Everything on this iPhone was kept.")
    }

    /// Writes the merged data to this device. Returns true if anything here changed.
    private func apply(_ result: BackupMergeResult, local: BackupPayload) -> Bool {
        let merged = result.payload
        var changed = false
        if result.clearLocalLearning { store.clearLearnedWords(); changed = true }
        if store.learned != merged.learned { store.learned = merged.learned; changed = true }
        if store.learnedPairs != merged.pairs { store.learnedPairs = merged.pairs; changed = true }
        if local.emoji != merged.emoji { store.recentEmoji = merged.emoji; changed = true }
        if let preferences = merged.preferences, preferences != local.preferences { store.preferences = preferences; changed = true }

        // Pinned text: unpin what another device removed, and add what another device pinned.
        var phrases = store.phrases
        let before = phrases
        let mergedIDs = Set(merged.pinned.map(\.id))
        for index in phrases.indices where phrases[index].pinned && !mergedIDs.contains(phrases[index].id) {
            phrases[index].pinned = false
        }
        let known = Set(phrases.map(\.id))
        for item in merged.pinned where !known.contains(item.id) {
            if let index = phrases.firstIndex(where: { $0.text == item.text }) { phrases[index].pinned = true }
            else { phrases.append(item) }
        }
        if phrases != before {
            store.phrases = phrases.sorted { $0.createdAt > $1.createdAt }
            changed = true
        }
        return changed
    }

    private static func encode(_ payload: BackupPayload) -> Data? {
        guard let json = try? JSONEncoder().encode(payload) else { return nil }
        return try? (json as NSData).compressed(using: .zlib) as Data
    }

    private static func decode(_ data: Data) -> BackupPayload? {
        guard let json = try? (data as NSData).decompressed(using: .zlib) as Data else { return nil }
        return try? JSONDecoder().decode(BackupPayload.self, from: json)
    }
}
