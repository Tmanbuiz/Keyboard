import XCTest
import TypingCore
@testable import KeyboardStorage

final class KeyboardStoreTests: XCTestCase {
    private var suites: [String] = []
    private func defaults() -> UserDefaults {
        let name = "KeyboardStoreTests." + UUID().uuidString
        suites.append(name)
        return UserDefaults(suiteName: name)!
    }
    override func setUp() {
        super.setUp()
        KeyboardStore.invalidateLearningCache()
    }
    override func tearDown() {
        for name in suites { UserDefaults.standard.removePersistentDomain(forName: name) }
        suites = []; KeyboardStore.invalidateLearningCache(); super.tearDown()
    }
    private func learningStore(_ local: UserDefaults) -> KeyboardStore {
        let store = KeyboardStore(local: local, group: nil, canWriteGroup: true)
        var preferences = store.preferences
        preferences.learnWords = true; store.preferences = preferences
        return store
    }
    func testLearnedWordsWaitInMemoryUntilSaved() {
        let local = defaults()
        let store = learningStore(local)
        store.learn("don’t")
        store.learnPair(previous: "i", word: "don’t")
        XCTAssertEqual(store.learned["don't"], 1)
        XCTAssertTrue(KeyboardStore.hasUnsavedLearning)
        XCTAssertNil(local.data(forKey: "learned.v1"), "a space press must not wait for storage")
        store.saveLearning()
        XCTAssertFalse(KeyboardStore.hasUnsavedLearning)
        KeyboardStore.invalidateLearningCache()
        XCTAssertEqual(store.learned["don't"], 1)
        XCTAssertEqual(store.learnedPairs["i"]?["don't"], 1)
    }
    func testClearingDropsWordsNotSavedYet() {
        let store = learningStore(defaults())
        store.learn("hello")
        store.clearLearnedWords()
        store.saveLearning()
        KeyboardStore.invalidateLearningCache()
        XCTAssertTrue(store.learned.isEmpty)
    }
    func testANewWordIsKeptWhenTheListIsFull() {
        let store = learningStore(defaults())
        var words: [String: Int] = [:]
        for index in 0..<BackupMerge.maxLearned { words["word\(index)"] = 1 }
        store.learned = words
        store.learn("fresh")
        XCTAssertEqual(store.learned.count, BackupMerge.maxLearned)
        XCTAssertEqual(store.learned["fresh"], 1)
    }
    func testChangedSettingsAreSeenAtOnce() {
        let store = learningStore(defaults())
        var preferences = store.preferences
        XCTAssertTrue(preferences.learnWords)
        preferences.privateMode = true; store.preferences = preferences
        store.learn("secret")
        XCTAssertNil(store.learned["secret"])
    }
    func testAppDeletionDoesNotResurrectFromKeyboardCache() throws {
        let shared = defaults(), appLocal = defaults(), keyboardLocal = defaults()
        let app = KeyboardStore(local: appLocal, group: shared, canWriteGroup: true)
        let keyboard = KeyboardStore(local: keyboardLocal, group: shared, canWriteGroup: false)
        app.capture("Delete me")
        keyboardLocal.set(try JSONEncoder().encode(app.phrases), forKey: "clips.v2")
        app.phrases = []
        XCTAssertTrue(keyboard.phrases.isEmpty)
        app.capture("Delete me")
        XCTAssertEqual(keyboard.phrases.map(\.text), ["Delete me"])
    }
    func testPrivateModePausesCaptureAndLearning() {
        let store = KeyboardStore(local: defaults(), group: nil, canWriteGroup: true)
        var preferences = store.preferences
        preferences.learnWords = true; preferences.privateMode = true
        store.preferences = preferences
        store.capture("Private text"); store.learn("hello"); store.learnPair(previous: "hello", word: "world")
        XCTAssertTrue(store.phrases.isEmpty)
        XCTAssertTrue(store.learned.isEmpty)
        XCTAssertTrue(store.learnedPairs.isEmpty)
        preferences.privateMode = false; store.preferences = preferences
        store.capture("Allowed text")
        XCTAssertEqual(store.phrases.first?.text, "Allowed text")
    }
    func testClearPersonalDataInvalidatesCachedLearning() {
        let shared = defaults(), keyboardLocal = defaults()
        let app = KeyboardStore(local: defaults(), group: shared, canWriteGroup: true)
        let keyboard = KeyboardStore(local: keyboardLocal, group: shared, canWriteGroup: false)
        keyboard.learned = ["hello": 2]
        app.clearPersonalData()
        XCTAssertTrue(keyboard.learned.isEmpty)
        XCTAssertTrue(keyboard.phrases.isEmpty)
    }
}

extension KeyboardStoreTests {
    func testReadOnlyResetHidesGroupHistoryAndPropagatesWhenAccessReturns() {
        let shared = defaults(), keyboardLocal = defaults()
        let app = KeyboardStore(local: defaults(), group: shared, canWriteGroup: true)
        app.capture("Old shared text"); app.learned = ["old": 2]
        let restricted = KeyboardStore(local: keyboardLocal, group: shared, canWriteGroup: false)
        restricted.clearPersonalData()
        XCTAssertTrue(restricted.phrases.isEmpty)
        XCTAssertTrue(restricted.learned.isEmpty)
        let enabled = KeyboardStore(local: keyboardLocal, group: shared, canWriteGroup: true)
        XCTAssertTrue(enabled.phrases.isEmpty)
        XCTAssertTrue(app.phrases.isEmpty)
        XCTAssertTrue(app.learned.isEmpty)
        enabled.capture("Fresh text")
        XCTAssertEqual(app.phrases.map(\.text), ["Fresh text"])
    }
    func testStaleClipboardSnapshotAndLegacyFallbackCannotRestoreDeletedText() throws {
        let shared = defaults(), appLocal = defaults(), keyboardLocal = defaults()
        let app = KeyboardStore(local: appLocal, group: shared, canWriteGroup: true)
        app.capture("Old text")
        let stale = app.phrases
        keyboardLocal.set(try JSONEncoder().encode(stale), forKey: "phrases.v1")
        let keyboard = KeyboardStore(local: keyboardLocal, group: shared, canWriteGroup: true)
        app.clearPersonalData()
        keyboard.phrases = stale
        XCTAssertTrue(keyboard.phrases.isEmpty)
        XCTAssertTrue(app.phrases.isEmpty)
    }
    func testClearLearningInvalidatesOtherProcessWithoutDeletingClipboard() {
        let shared = defaults(), keyboardLocal = defaults()
        let app = KeyboardStore(local: defaults(), group: shared, canWriteGroup: true)
        let keyboard = KeyboardStore(local: keyboardLocal, group: shared, canWriteGroup: false)
        app.capture("Keep clip")
        keyboard.learned = ["hello": 5]; keyboard.learnedPairs = ["hello": ["world": 2]]
        app.clearLearnedWords()
        XCTAssertTrue(keyboard.learned.isEmpty)
        XCTAssertTrue(keyboard.learnedPairs.isEmpty)
        XCTAssertEqual(keyboard.phrases.map(\.text), ["Keep clip"])
    }
}

extension KeyboardStoreTests {
    func testResetGenerationOverridesFutureDatedCache() {
        let shared = defaults(), keyboardLocal = defaults()
        let app = KeyboardStore(local: defaults(), group: shared, canWriteGroup: true)
        let keyboard = KeyboardStore(local: keyboardLocal, group: shared, canWriteGroup: false)
        keyboard.learned = ["cached": 1]
        keyboardLocal.set(Date.distantFuture, forKey: "learned.v1.updatedAt")
        app.clearLearnedWords()
        XCTAssertTrue(keyboard.learned.isEmpty)
        app.capture("Future clip")
        var stale = app.phrases
        stale[0].createdAt = .distantFuture
        app.phrases = stale
        app.clearPersonalData()
        app.phrases = stale
        XCTAssertTrue(app.phrases.isEmpty)
    }
}

extension KeyboardStoreTests {
    func testPersonalResetPreservesPrivacyPreferences() {
        let shared = defaults()
        let store = KeyboardStore(local: defaults(), group: shared, canWriteGroup: true)
        var preferences = store.preferences
        preferences.privateMode = true
        store.preferences = preferences
        store.clearPersonalData()
        XCTAssertTrue(store.preferences.privateMode)
        let other = KeyboardStore(local: defaults(), group: shared, canWriteGroup: false)
        XCTAssertTrue(other.preferences.privateMode)
    }
    func testMemoryPeaksKeepTheHighestPerScreenUntilReset() {
        let store = KeyboardStore(local: defaults(), group: nil, canWriteGroup: true)
        store.recordMemoryPeaks(["typing": 40, "emoji": 90])
        store.recordMemoryPeaks(["typing": 35, "emoji": 120, "writing": 50])
        XCTAssertEqual(store.memoryPeakScreens, ["typing": 40, "emoji": 120, "writing": 50])
        store.recordMemoryWarning(screen: "emoji", headroomMB: 20, detail: "used 150 MB")
        store.lastRestartNote = "emoji screen, 160 MB used, 16 MB left"
        store.resetHealthCounters()
        XCTAssertEqual(store.memoryPeakScreens, [:])
        XCTAssertEqual(store.memoryWarningScreens, [:])
        XCTAssertNil(store.lastRestartNote)
        XCTAssertNil(store.lowestMemoryDetail)
    }
}
