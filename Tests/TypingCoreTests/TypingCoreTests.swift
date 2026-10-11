import XCTest
@testable import TypingCore

final class TypingCoreTests: XCTestCase {
    let engine = SuggestionEngine.bundled()

    func testBundledLexiconHasAllLanguages() {
        XCTAssertGreaterThan(engine.entries.count, 300)
        for language in KeyboardLanguage.allCases {
            XCTAssertTrue(engine.entries.contains { $0.language == language })
        }
    }

    func testUnicodeCursorContext() {
        XCTAssertEqual(TextContext.currentWord(in: "Ẹ káàárọ̀"), "káàárọ̀")
        XCTAssertEqual(TextContext.currentWord(in: "don't"), "don't")
        XCTAssertEqual(TextContext.currentWord(in: "hello 👋"), "")
        XCTAssertEqual(TextContext.previousWord(in: "how are"), "how")
        XCTAssertTrue(TextContext.shouldCapitalize(after: "Hello! "))
        XCTAssertFalse(TextContext.shouldCapitalize(after: "hello "))
    }

    func testConservativeCorrectionAndDialects() {
        XCTAssertEqual(engine.autocorrection(for: "teh", language: .english), "the")
        XCTAssertEqual(engine.autocorrection(for: "hellp", language: .english), "hello")
        XCTAssertNil(engine.autocorrection(for: "Bukola", language: .english))
        XCTAssertNil(engine.autocorrection(for: "OTP", language: .english))
        XCTAssertNil(engine.autocorrection(for: "dey", language: .pidgin))
        XCTAssertNil(engine.autocorrection(for: "ẹsẹ", language: .yoruba))
        XCTAssertNil(engine.autocorrection(for: "hellp", language: .english, protectedWords: ["hellp"]))
        XCTAssertNil(engine.autocorrection(for: "samsung123", language: .english))
    }

    func testCompletionAndNextWord() {
        XCTAssertEqual(engine.suggestions(for: "hell", language: .english).first?.text, "hello")
        XCTAssertEqual(engine.suggestions(for: "", previous: "thank", language: .english).first?.text, "you")
        let custom = engine.suggestions(for: "wian", language: .english, learned: ["wiantribe": 10])
        XCTAssertTrue(custom.contains { $0.text == "wiantribe" })
    }

    func testCorrectionUndoRequiresCursorContext() {
        let correction = CorrectionRecord(original: "teh", replacement: "the", contextBefore: "I saw teh")
        XCTAssertTrue(correction.canUndo(context: "I saw the "))
        XCTAssertFalse(correction.canUndo(context: "I saw the next"))
        XCTAssertFalse(correction.canUndo(context: "You saw the "))
    }

    func testGlideDecodesActualKeyPath() {
        var centers: [Character: GlidePoint] = [:]
        for (row, letters) in ["qwertyuiop", "asdfghjkl", "zxcvbnm"].enumerated() {
            for (column, letter) in letters.enumerated() { centers[letter] = GlidePoint(x: Double(column) + Double(row) * 0.3, y: Double(row)) }
        }
        let decoder = GlideDecoder()
        let ideal = Array("hello").compactMap { centers[$0] }
        let path = decoder.resample(ideal, count: 80)
        let candidates = decoder.decode(path: path, centers: centers, entries: engine.entries, language: .english, keyWidth: 1)
        XCTAssertEqual(candidates.first?.word, "hello")
        XCTAssertTrue(decoder.decode(path: [GlidePoint(x: 40, y: 40), GlidePoint(x: 50, y: 45), GlidePoint(x: 60, y: 40)],
                                     centers: centers, entries: engine.entries, language: .english, keyWidth: 1).isEmpty)
    }

    func testLearningDoesNotRetainAddressesOrCodes() {
        XCTAssertFalse(TextContext.canLearn("someone@example.com"))
        XCTAssertFalse(TextContext.canLearn("123456"))
        XCTAssertFalse(TextContext.canLearn("MyPassword123"))
        XCTAssertTrue(TextContext.canLearn("wiantribe"))
    }

    func testPreferencesRoundTrip() throws {
        var preferences = KeyboardPreferences()
        preferences.language = .yoruba; preferences.handMode = .right
        XCTAssertEqual(try JSONDecoder().decode(KeyboardPreferences.self, from: JSONEncoder().encode(preferences)), preferences)
        XCTAssertFalse(preferences.learnWords)
        XCTAssertFalse(preferences.clipboardHistory)
    }

    func testOlderPreferencesKeepTheirValues() throws {
        let old = #"{"language":"pidgin","theme":"rose","handMode":"left","numberRow":false,"autocorrect":true,"predictions":true,"swipeTyping":true,"autoCapitalization":true,"doubleSpacePeriod":true,"haptics":true,"learnWords":false,"height":340}"#
        let decoded = try JSONDecoder().decode(KeyboardPreferences.self, from: Data(old.utf8))
        XCTAssertEqual(decoded.language, .pidgin); XCTAssertEqual(decoded.theme, .rose)
        XCTAssertFalse(decoded.numberRow); XCTAssertEqual(decoded.height, 340)
        XCTAssertFalse(decoded.clipboardHistory); XCTAssertEqual(decoded.clipboardDays, 7)
    }

    func testClipboardNewestFirstAndDeduplicates() {
        var items: [SavedPhrase] = []
        for text in ["one", "two", "three", "two"] { items = ClipboardHistory.adding(text, to: items) }
        XCTAssertEqual(items.map(\.text), ["two", "three", "one"])
        XCTAssertEqual(ClipboardHistory.adding("   ", to: items), items)
    }

    func testClipboardDuplicateKeepsPinAndIdentity() {
        var items = ClipboardHistory.adding("address", to: [], pinned: true)
        let id = items[0].id
        items = ClipboardHistory.adding("other", to: items)
        items = ClipboardHistory.adding("address", to: items)
        XCTAssertEqual(items[0].text, "address"); XCTAssertTrue(items[0].pinned); XCTAssertEqual(items[0].id, id)
    }

    func testClipboardCapsRecentButKeepsPinned() {
        var items = ClipboardHistory.adding("keep me", to: [], pinned: true)
        for i in 0..<(ClipboardHistory.maxRecent + 10) { items = ClipboardHistory.adding("clip \(i)", to: items) }
        XCTAssertEqual(items.filter { !$0.pinned }.count, ClipboardHistory.maxRecent)
        XCTAssertTrue(items.contains { $0.text == "keep me" && $0.pinned })
        XCTAssertEqual(items.first?.text, "clip \(ClipboardHistory.maxRecent + 9)")
    }

    func testClipboardExpiresOnlyRecentItems() {
        let now = Date()
        let old = now.addingTimeInterval(-10 * 86_400)
        let items = [SavedPhrase(text: "old clip", createdAt: old), SavedPhrase(text: "old pin", pinned: true, createdAt: old),
                     SavedPhrase(text: "new clip", createdAt: now)]
        XCTAssertEqual(ClipboardHistory.pruned(items, now: now, keepDays: 7).map(\.text), ["old pin", "new clip"])
        XCTAssertEqual(ClipboardHistory.pruned(items, now: now, keepDays: 30).count, 3)
        XCTAssertEqual(ClipboardHistory.ordered(items).first?.text, "old pin")
    }

    func testClipboardSkipsSensitiveContent() {
        XCTAssertFalse(ClipboardHistory.shouldCapture("hunter2", types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"]))
        XCTAssertFalse(ClipboardHistory.shouldCapture(" \n "))
        XCTAssertTrue(ClipboardHistory.shouldCapture("See you at 5", types: ["public.utf8-plain-text"]))
        XCTAssertEqual(ClipboardHistory.preview("Hello there\nsecond line"), "Hello there")
        XCTAssertEqual(ClipboardHistory.preview(String(repeating: "a", count: 30), length: 5), "aaaaa…")
    }
}
