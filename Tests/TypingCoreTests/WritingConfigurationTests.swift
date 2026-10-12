import XCTest
@testable import TypingCore

final class WritingConfigurationTests: XCTestCase {
    func testExplicitProvidersNeverFallBackToApple() {
        XCTAssertEqual(WritingProvider.groq.routes, [.groq])
        XCTAssertEqual(WritingProvider.service.routes, [.service])
        XCTAssertEqual(WritingProvider.apple.routes, [.onDevice])
        XCTAssertEqual(WritingProvider.automatic.routes, [.onDevice, .service])
    }
    func testPreferencesUpgradePreservesExistingChoices() throws {
        let old = Data(#"{"language":"en","height":330,"clipboardHistory":true,"theme":"ocean"}"#.utf8)
        let preferences = try JSONDecoder().decode(KeyboardPreferences.self, from: old)
        XCTAssertEqual(preferences.writingProvider, .automatic)
        XCTAssertEqual(preferences.height, 330); XCTAssertTrue(preferences.clipboardHistory)
        XCTAssertEqual(preferences.theme, .ocean)
        var next = preferences; next.writingProvider = .groq
        XCTAssertEqual(try JSONDecoder().decode(KeyboardPreferences.self, from: JSONEncoder().encode(next)), next)
    }
    func testGroqConfigurationRejectsHeaderInjectionAndMalformedModel() {
        XCTAssertTrue(GroqConfiguration(key: " gsk_TEST_ONLY ", model: "openai/gpt-oss-20b").valid)
        XCTAssertFalse(GroqConfiguration(key: "gsk_KEY\nInjected").valid)
        XCTAssertFalse(GroqConfiguration(key: "gsk_TEST_ONLY", model: "../bad?token=anything").valid)
        XCTAssertFalse(GroqConfiguration(key: "", model: GroqConfiguration.defaultModel).valid)
    }
    func testEditingUnicodeResultKeepsCursorAndOriginalSeparate() {
        let original = "Original in host app"
        var edit = WritingEditBuffer(text: "Ẹ káàárọ̀ 👨‍👩‍👧")
        edit.delete(); XCTAssertEqual(edit.text, "Ẹ káàárọ̀ ")
        edit.move(-edit.cursor); edit.insert("Hello! ")
        XCTAssertEqual(edit.text, "Hello! Ẹ káàárọ̀ ")
        XCTAssertEqual(edit.before, "Hello! ")
        XCTAssertEqual(original, "Original in host app")
        edit.move(1000); XCTAssertEqual(edit.cursor, edit.text.count)
        edit.move(-1000); edit.delete(); XCTAssertEqual(edit.cursor, 0)
    }
}
