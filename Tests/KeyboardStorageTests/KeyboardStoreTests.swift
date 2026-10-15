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
    override func tearDown() {
        for name in suites { UserDefaults.standard.removePersistentDomain(forName: name) }
        suites = []; super.tearDown()
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
