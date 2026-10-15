import XCTest
@testable import TypingCore

final class TypingCoreTests: XCTestCase {
    let engine = SuggestionEngine.make(primary: .english)

    func testCatalogAndDictionariesLoad() {
        XCTAssertGreaterThanOrEqual(LanguageCatalog.all.count, 25)
        XCTAssertEqual(Set(LanguageCatalog.all.map(\.code)).count, LanguageCatalog.all.count)
        for pack in LanguageCatalog.all {
            XCTAssertEqual(pack.rows.count, 3, pack.code)
            XCTAssertEqual(pack.hasDictionary, Lexicon.load(code: pack.code) != nil, pack.code)
        }
        XCTAssertGreaterThan(Lexicon.load(code: "fr")?.count ?? 0, 20_000)
        XCTAssertTrue(Lexicon.load(code: "yo")?.contains("káàárọ̀") ?? false)
        XCTAssertFalse(KeyboardLanguage("ar").pack.isCased)
        XCTAssertTrue(KeyboardLanguage("ar").pack.rightToLeft)
        XCTAssertEqual(KeyboardLanguage("tr").pack.uppercased("i"), "İ")
        XCTAssertEqual(KeyboardLanguage("zz"), .english)
    }

    func testDeviceLanguagesAndLegacyNames() throws {
        XCTAssertEqual(LanguageCatalog.deviceLanguages(["fr-CA", "en-US", "fr-FR", "xx"]).map(\.code), ["fr", "en"])
        XCTAssertEqual(LanguageCatalog.deviceLanguages(["nn-NO", "tl"]).map(\.code), ["nb", "fil"])
        let decoded = try JSONDecoder().decode([KeyboardLanguage].self, from: Data(#"["english","yoruba","pidgin","de"]"#.utf8))
        XCTAssertEqual(decoded.map(\.code), ["en", "yo", "pcm", "de"])
    }

    func testOtherLanguagesSuggestAndCorrect() {
        let french = SuggestionEngine.make(primary: KeyboardLanguage("fr"))
        XCTAssertTrue(french.suggestions(for: "bonj").contains { $0.text == "bonjour" })
        let german = SuggestionEngine.make(primary: KeyboardLanguage("de"))
        XCTAssertTrue(german.suggestions(for: "Schö").contains { $0.text.hasPrefix("Schö") })
        let russian = SuggestionEngine.make(primary: KeyboardLanguage("ru"))
        XCTAssertTrue(russian.suggestions(for: "приве").contains { $0.text == "привет" })
        XCTAssertNil(SuggestionEngine.make(primary: .yoruba).autocorrection(for: "ẹsẹ"))
    }

    func testMultilingualSuggestionsMixSameScriptOnly() {
        let mixed = SuggestionEngine.make(primary: .english, others: [KeyboardLanguage("es"), KeyboardLanguage("ru")])
        XCTAssertEqual(mixed.lexicons.map(\.code), ["en", "es"])
        XCTAssertTrue(mixed.suggestions(for: "graci").contains { $0.text == "gracias" })
        // A Spanish word is known, so it is not "corrected" into English.
        XCTAssertNil(mixed.autocorrection(for: "hola"))
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
        XCTAssertEqual(engine.autocorrection(for: "teh"), "the")
        XCTAssertTrue(["help", "hello"].contains(engine.autocorrection(for: "hellp") ?? ""))
        XCTAssertEqual(engine.autocorrection(for: "becuase"), "because")
        XCTAssertNil(engine.autocorrection(for: "Bukola"))
        XCTAssertNil(engine.autocorrection(for: "OTP"))
        XCTAssertNil(SuggestionEngine.make(primary: .pidgin).autocorrection(for: "dey"))
        XCTAssertNil(engine.autocorrection(for: "hellp", protectedWords: ["hellp"]))
        XCTAssertNil(engine.autocorrection(for: "samsung123"))
        XCTAssertNil(engine.autocorrection(for: "keyboard"))
    }

    func testCompletionAndNextWord() {
        XCTAssertTrue(engine.suggestions(for: "hell").contains { $0.text == "hello" })
        XCTAssertEqual(engine.suggestions(for: "Hell").first?.text.first, "H")
        XCTAssertEqual(engine.suggestions(for: "", previous: "thank").first?.text, "you")
        let custom = engine.suggestions(for: "wian", learned: ["wiantribe": 10])
        XCTAssertTrue(custom.contains { $0.text == "wiantribe" })
        let personal = engine.suggestions(for: "", previous: "see", learnedPairs: ["see": ["tomorrow": 4]])
        XCTAssertEqual(personal.first?.text, "tomorrow")
        XCTAssertEqual(SuggestionEngine.editDistance("kitten", "sitting"), 3)
        XCTAssertEqual(SuggestionEngine.editDistance("kitten", "sitting", limit: 1), 2)
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
        let starts = decoder.startLetters(path: path, centers: centers, keyWidth: 1)
        XCTAssertTrue(starts.contains("h"))
        let candidates = decoder.decode(path: path, centers: centers, words: engine.glideWords(startingWith: starts), keyWidth: 1)
        XCTAssertEqual(candidates.first?.word, "hello")
        let far = [GlidePoint(x: 40, y: 40), GlidePoint(x: 50, y: 45), GlidePoint(x: 60, y: 40)]
        XCTAssertTrue(decoder.decode(path: far, centers: centers, words: engine.glideWords(startingWith: decoder.startLetters(path: far, centers: centers, keyWidth: 1)), keyWidth: 1).isEmpty)
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
        XCTAssertEqual(decoded.languages, [.pidgin]); XCTAssertTrue(decoded.multilingual)
        XCTAssertTrue(decoded.keySounds); XCTAssertEqual(decoded.accent, .theme)
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

    func testWritingAssistActionsAreComplete() {
        XCTAssertEqual(Set(WritingAction.rewrites + WritingAction.formats + [.translate]), Set(WritingAction.allCases))
        for action in WritingAction.allCases {
            XCTAssertFalse(action.title.isEmpty); XCTAssertGreaterThan(action.instruction.count, 20)
        }
        // v0.1 stored action names must still decode.
        XCTAssertEqual(try JSONDecoder().decode([WritingAction].self, from: Data(#"["grammar","casual"]"#.utf8)), [.grammar, .casual])
    }

    func testEmojiPredictions() {
        let catalog = EmojiCatalog.shared
        catalog.warmUp()
        XCTAssertEqual(catalog.predictions(for: "love", languages: ["en"]).first?.emoji.replacingOccurrences(of: "\u{FE0F}", with: ""), "❤")
        XCTAssertEqual(catalog.predictions(for: "Pizza", languages: ["en"]).first?.emoji, "🍕")
        XCTAssertTrue(catalog.predictions(for: "the", languages: ["en"]).isEmpty)
        XCTAssertTrue(catalog.predictions(for: "x", languages: ["en"]).isEmpty)
        XCTAssertTrue(catalog.predictions(for: "zzqqxx", languages: ["en"]).isEmpty)
        // A recently used emoji is offered first.
        let recent = catalog.predictions(for: "love", languages: ["en"], recent: ["🥰"])
        XCTAssertEqual(recent.first?.emoji, "🥰")
    }

    func testClipboardRejectsOversizeWithoutChangingHistory() {
        let existing = [SavedPhrase(text: "Keep me")]
        let large = String(repeating: "a", count: ClipboardHistory.maxLength + 1)
        XCTAssertFalse(ClipboardHistory.shouldCapture(large))
        XCTAssertEqual(ClipboardHistory.adding(large, to: existing), existing)
        XCTAssertTrue(ClipboardHistory.shouldCapture(String(large.prefix(ClipboardHistory.maxLength))))
    }
    func testClipboardDuplicatePreservesFolder() {
        var item = SavedPhrase(text: "Hello")
        item.folder = "Work"
        XCTAssertEqual(ClipboardHistory.adding("Hello", to: [item]).first?.folder, "Work")
    }
    func testPrivateModeSurvivesPreferencesRoundTrip() throws {
        var preferences = KeyboardPreferences()
        preferences.privateMode = true
        let data = try JSONEncoder().encode(preferences)
        XCTAssertTrue(try JSONDecoder().decode(KeyboardPreferences.self, from: data).privateMode)
    }
}
