import Foundation

/// What the optional iCloud backup carries between a person's devices: learned word counts, pinned
/// text, recent emoji and keyboard settings. Recent clipboard items are never included.
public struct BackupPayload: Codable, Equatable {
    public var version = 1
    /// Changes whenever learned words are cleared, so clearing on one device clears the others.
    public var learningEpoch: String
    public var learned: [String: Int]
    public var pairs: [String: [String: Int]]
    public var pinned: [SavedPhrase]
    public var emoji: [String]
    public var preferences: KeyboardPreferences?

    public init(learningEpoch: String = "", learned: [String: Int] = [:], pairs: [String: [String: Int]] = [:],
                pinned: [SavedPhrase] = [], emoji: [String] = [], preferences: KeyboardPreferences? = nil) {
        self.learningEpoch = learningEpoch; self.learned = learned; self.pairs = pairs
        self.pinned = pinned; self.emoji = emoji; self.preferences = preferences
    }
}

public struct BackupMergeResult: Equatable {
    public var payload: BackupPayload
    /// Another device cleared learned words, so this device must clear its own before taking the payload.
    public var clearLocalLearning: Bool
}

/// Combines this device's data with the iCloud copy. `base` is what this device last synced, which
/// shows what changed here and what changed elsewhere. Kept free of iCloud so it can be unit tested.
public enum BackupMerge {
    public static let maxLearned = 1000
    public static let maxPairs = 1500
    public static let maxFollowers = 12
    public static let maxEmoji = 40

    /// Consent switches and screen-size choices belong to each device and are never copied across.
    public static func keepingDeviceChoices(_ preferences: KeyboardPreferences, from device: KeyboardPreferences) -> KeyboardPreferences {
        var result = preferences
        result.privateMode = device.privateMode
        result.clipboardHistory = device.clipboardHistory
        result.learnWords = device.learnWords
        result.height = device.height
        result.handMode = device.handMode
        return result
    }

    public static func merge(base: BackupPayload?, local: BackupPayload, remote: BackupPayload?,
                             locallyCleared: Bool, newEpoch: String) -> BackupMergeResult {
        var result = local
        let syncedBefore = !local.learningEpoch.isEmpty
        guard let remote else {
            // Nothing in iCloud yet: this device's data becomes the backup.
            if !syncedBefore || locallyCleared { result.learningEpoch = newEpoch }
            return BackupMergeResult(payload: capped(result), clearLocalLearning: false)
        }
        var clearLocal = false
        if syncedBefore && locallyCleared {
            // Cleared here: this device's (now smaller) list replaces the backup under a new epoch.
            result.learningEpoch = newEpoch
        } else if syncedBefore && remote.learningEpoch != local.learningEpoch {
            // Cleared on another device.
            result.learningEpoch = remote.learningEpoch
            result.learned = remote.learned; result.pairs = remote.pairs
            clearLocal = true
        } else {
            result.learningEpoch = remote.learningEpoch.isEmpty ? newEpoch : remote.learningEpoch
            result.learned = mergedCounts(local.learned, remote.learned)
            result.pairs = mergedPairs(local.pairs, remote.pairs)
        }

        if let base {
            result.emoji = local.emoji != base.emoji ? local.emoji : remote.emoji
        } else {
            var seen = Set<String>()
            result.emoji = (local.emoji + remote.emoji).filter { seen.insert($0).inserted }
        }

        if let remotePreferences = remote.preferences {
            if let localPreferences = local.preferences {
                // Settings changed here since the last sync win; otherwise take the backup's.
                let changedHere = base?.preferences.map { keepingDeviceChoices(localPreferences, from: $0) != $0 } ?? false
                result.preferences = changedHere ? localPreferences : keepingDeviceChoices(remotePreferences, from: localPreferences)
            } else {
                result.preferences = remotePreferences
            }
        }

        // Pinned text: keep everything pinned on either side, except what either side removed since the last sync.
        let baseIDs = Set((base?.pinned ?? []).map(\.id))
        let removed = baseIDs.subtracting(local.pinned.map(\.id)).union(baseIDs.subtracting(remote.pinned.map(\.id)))
        var seenIDs = Set<UUID>(), seenText = Set<String>(), pinned: [SavedPhrase] = []
        for item in local.pinned + remote.pinned where !removed.contains(item.id) {
            guard seenIDs.insert(item.id).inserted, seenText.insert(item.text).inserted else { continue }
            var kept = item; kept.pinned = true
            pinned.append(kept)
        }
        result.pinned = pinned
        return BackupMergeResult(payload: capped(result), clearLocalLearning: clearLocal)
    }

    /// Enforces the same size limits the keyboard uses, keeping the most used entries.
    static func capped(_ payload: BackupPayload) -> BackupPayload {
        var result = payload
        result.learned = top(result.learned, maxLearned)
        result.pairs = result.pairs.mapValues { top($0, maxFollowers) }
        if result.pairs.count > maxPairs {
            let keep = result.pairs.map { (key: $0.key, total: $0.value.values.reduce(0, +)) }
                .sorted { $0.total == $1.total ? $0.key < $1.key : $0.total > $1.total }.prefix(maxPairs).map(\.key)
            let kept = Set(keep)
            result.pairs = result.pairs.filter { kept.contains($0.key) }
        }
        result.emoji = Array(result.emoji.prefix(maxEmoji))
        result.pinned = Array(result.pinned.sorted { $0.createdAt > $1.createdAt }.prefix(ClipboardHistory.maxPinned))
        return result
    }

    static func top(_ counts: [String: Int], _ limit: Int) -> [String: Int] {
        guard counts.count > limit else { return counts }
        let kept = counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.prefix(limit)
        return Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
    }

    static func mergedCounts(_ lhs: [String: Int], _ rhs: [String: Int]) -> [String: Int] {
        lhs.merging(rhs) { max($0, $1) }
    }

    static func mergedPairs(_ lhs: [String: [String: Int]], _ rhs: [String: [String: Int]]) -> [String: [String: Int]] {
        lhs.merging(rhs) { mergedCounts($0, $1) }
    }
}
