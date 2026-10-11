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
    }
}
