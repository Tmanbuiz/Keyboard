import XCTest
@testable import TypingCore

final class BackupMergeTests: XCTestCase {
    private func merge(base: BackupPayload? = nil, local: BackupPayload, remote: BackupPayload?, cleared: Bool = false) -> BackupMergeResult {
        BackupMerge.merge(base: base, local: local, remote: remote, locallyCleared: cleared, newEpoch: "new")
    }

    func testFirstBackupUsesThisDevice() {
        let local = BackupPayload(learned: ["hello": 3], emoji: ["😀"])
        let result = merge(local: local, remote: nil, cleared: true)
        XCTAssertEqual(result.payload.learned, ["hello": 3])
        XCTAssertEqual(result.payload.learningEpoch, "new")
        XCTAssertFalse(result.clearLocalLearning)
    }

    func testNewDeviceJoinsWithoutLosingItsWords() {
        let local = BackupPayload(learned: ["hello": 3, "bola": 1], pairs: ["good": ["day": 2]])
        let remote = BackupPayload(learningEpoch: "e1", learned: ["hello": 5, "ada": 2], pairs: ["good": ["day": 1, "night": 4]])
        // An old clear on this device must not wipe the backup the first time it joins.
        let result = merge(local: local, remote: remote, cleared: true)
        XCTAssertEqual(result.payload.learningEpoch, "e1")
        XCTAssertEqual(result.payload.learned, ["hello": 5, "bola": 1, "ada": 2])
        XCTAssertEqual(result.payload.pairs, ["good": ["day": 2, "night": 4]])
        XCTAssertFalse(result.clearLocalLearning)
    }

    func testClearHereReplacesBackup() {
        let local = BackupPayload(learningEpoch: "e1", learned: [:])
        let remote = BackupPayload(learningEpoch: "e1", learned: ["hello": 5])
        let result = merge(base: remote, local: local, remote: remote, cleared: true)
        XCTAssertEqual(result.payload.learned, [:])
        XCTAssertEqual(result.payload.learningEpoch, "new")
    }

    func testClearOnAnotherDeviceClearsThisOne() {
        let local = BackupPayload(learningEpoch: "e1", learned: ["hello": 5, "secret": 1])
        let remote = BackupPayload(learningEpoch: "e2", learned: ["fresh": 1])
        let result = merge(base: local, local: local, remote: remote)
        XCTAssertTrue(result.clearLocalLearning)
        XCTAssertEqual(result.payload.learned, ["fresh": 1])
        XCTAssertEqual(result.payload.learningEpoch, "e2")
    }

    func testPinnedTextAddsAndRemovalsTravelBothWays() {
        let kept = SavedPhrase(text: "kept", pinned: true), removedHere = SavedPhrase(text: "removed here", pinned: true)
        let removedThere = SavedPhrase(text: "removed there", pinned: true)
        let addedHere = SavedPhrase(text: "added here", pinned: true), addedThere = SavedPhrase(text: "added there", pinned: true)
        let base = BackupPayload(learningEpoch: "e1", pinned: [kept, removedHere, removedThere])
        let local = BackupPayload(learningEpoch: "e1", pinned: [kept, removedThere, addedHere])
        let remote = BackupPayload(learningEpoch: "e1", pinned: [kept, removedHere, addedThere])
        let result = merge(base: base, local: local, remote: remote)
        XCTAssertEqual(Set(result.payload.pinned.map(\.text)), ["kept", "added here", "added there"])
    }

    func testSameTextPinnedOnTwoDevicesIsKeptOnce() {
        let local = BackupPayload(pinned: [SavedPhrase(text: "my address", pinned: true)])
        let remote = BackupPayload(learningEpoch: "e1", pinned: [SavedPhrase(text: "my address", pinned: true)])
        XCTAssertEqual(merge(local: local, remote: remote).payload.pinned.count, 1)
    }

    func testSettingsFollowTheLatestChangeButDeviceChoicesStay() {
        var synced = KeyboardPreferences(); synced.numberRow = true; synced.learnWords = false; synced.height = 300
        var here = synced; here.learnWords = true; here.height = 240
        var there = synced; there.numberRow = false; there.learnWords = false; there.height = 360
        let base = BackupPayload(learningEpoch: "e1", preferences: synced)
        let local = BackupPayload(learningEpoch: "e1", preferences: here)
        let remote = BackupPayload(learningEpoch: "e1", preferences: there)
        // Only device choices changed here, so the other device's setting arrives and the device choices stay.
        let merged = merge(base: base, local: local, remote: remote).payload.preferences
        XCTAssertEqual(merged?.numberRow, false)
        XCTAssertEqual(merged?.learnWords, true)
        XCTAssertEqual(merged?.height, 240)
        // A setting changed here since the last sync wins.
        var changed = here; changed.autocorrect.toggle()
        let kept = merge(base: base, local: BackupPayload(learningEpoch: "e1", preferences: changed), remote: remote).payload.preferences
        XCTAssertEqual(kept, changed)
    }

    func testLimitsKeepTheMostUsedWords() {
        var many: [String: Int] = [:]
        for index in 0..<(BackupMerge.maxLearned + 50) { many["w\(index)"] = index + 1 }
        let result = merge(local: BackupPayload(learned: many), remote: nil)
        XCTAssertEqual(result.payload.learned.count, BackupMerge.maxLearned)
        XCTAssertNil(result.payload.learned["w0"])
        XCTAssertNotNil(result.payload.learned["w\(BackupMerge.maxLearned + 49)"])
    }

    func testPayloadSurvivesEncoding() throws {
        let payload = BackupPayload(learningEpoch: "e1", learned: ["hello": 2], pairs: ["a": ["b": 1]],
                                    pinned: [SavedPhrase(text: "pin", pinned: true, createdAt: Date(timeIntervalSince1970: 1_700_000_000))],
                                    emoji: ["😀"], preferences: KeyboardPreferences())
        let decoded = try JSONDecoder().decode(BackupPayload.self, from: JSONEncoder().encode(payload))
        XCTAssertEqual(decoded, payload)
    }
}

final class WordPatternTests: XCTestCase {
    func testContextFindsLastTwoWordsAndSentenceStarts() {
        XCTAssertTrue(TextContext.patternContext(in: "") == (TextContext.sentenceStart, ""))
        XCTAssertTrue(TextContext.patternContext(in: "All done. ") == (TextContext.sentenceStart, ""))
        XCTAssertTrue(TextContext.patternContext(in: "Hi\nto") == (TextContext.sentenceStart, ""))
        XCTAssertTrue(TextContext.patternContext(in: "See you ") == ("you", "see"))
        XCTAssertTrue(TextContext.patternContext(in: "See you tom") == ("you", "see"))
        XCTAssertTrue(TextContext.patternContext(in: "Well, you ") == ("you", ""))
        XCTAssertTrue(TextContext.patternContext(in: "Well, ") == ("", ""))
    }

    func testTwoWordHabitBeatsOneWordHabit() {
        let engine = SuggestionEngine.make(primary: .english)
        let pairs = ["you": ["are": 9], "see you": ["tomorrow": 2], "thank you": ["so": 3]]
        XCTAssertEqual(engine.nextWords(after: "you", before: "see", learnedPairs: pairs).first, "tomorrow")
        XCTAssertEqual(engine.nextWords(after: "you", before: "thank", learnedPairs: pairs).first, "so")
        XCTAssertEqual(engine.nextWords(after: "you", learnedPairs: pairs).first, "are")
        // While typing, a word the person uses after these two words comes first.
        let typing = engine.suggestions(for: "t", previous: "you", before: "see", learnedPairs: pairs)
        XCTAssertEqual(typing.first?.text, "tomorrow")
    }

    func testSentenceStartersAreLearned() {
        let engine = SuggestionEngine.make(primary: .english)
        let next = engine.nextWords(after: TextContext.sentenceStart, learnedPairs: [TextContext.sentenceStart: ["good": 3, "please": 1]])
        XCTAssertEqual(Array(next.prefix(2)), ["good", "please"])
    }

    func testRecentHabitsOutweighOldOnes() {
        var followers = ["old": 500, "rare": 1]
        followers = TextContext.reinforced(followers, word: "new")
        XCTAssertEqual(followers["old"], TextContext.recencyCeiling)
        for _ in 0..<40 { followers = TextContext.reinforced(followers, word: "new", weight: 2) }
        XCTAssertGreaterThan(followers["new"] ?? 0, followers["old"] ?? 0)
        XCTAssertLessThanOrEqual(followers.values.max() ?? 0, TextContext.recencyCeiling)
    }

    func testApostropheWordsAreLearnedAndUsedAsContext() {
        for word in ["don't", "i'm", "c'est", "j'ai", "aujourd'hui", "п'ять"] { XCTAssertTrue(TextContext.canLearn(word), word) }
        for word in ["'tis", "dogs'", "don''t", "it's'", "a'b'c'd"] { XCTAssertFalse(TextContext.canLearn(word), word) }
        XCTAssertTrue(TextContext.canBeContext("i'm"))
        XCTAssertEqual(TextContext.learningForm("don’t"), "don't")
        XCTAssertEqual(TextContext.learningForm("'hello'"), "hello")
        XCTAssertTrue(TextContext.patternContext(in: "I’m going ") == ("going", "i'm"))
        XCTAssertTrue(TextContext.patternContext(in: "I'm ") == ("i'm", ""))
    }

    func testCurlyApostrophesMatchAndEnglishIIsCapitalised() {
        let engine = SuggestionEngine.make(primary: .english)
        XCTAssertEqual(engine.suggestions(for: "", previous: "and", learnedPairs: ["and": ["i'm": 5]]).first?.text, "I'm")
        XCTAssertTrue(engine.suggestions(for: "don’").contains { $0.text == "don't" })
        XCTAssertEqual(TextContext.properCase("i've", language: "en"), "I've")
        XCTAssertEqual(TextContext.properCase("it", language: "en"), "it")
        XCTAssertEqual(TextContext.properCase("i", language: "fr"), "i")
    }

    func testFollowerListStaysSmallAndKeepsTheNewWord() {
        var followers: [String: Int] = [:]
        for index in 0..<TextContext.maxFollowers { followers["w\(index)"] = index + 2 }
        followers = TextContext.reinforced(followers, word: "fresh")
        XCTAssertEqual(followers.count, TextContext.maxFollowers)
        XCTAssertNotNil(followers["fresh"])
        XCTAssertNil(followers["w0"])
    }
}
