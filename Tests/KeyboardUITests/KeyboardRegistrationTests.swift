import XCTest

/// Exercises iOS extension registration and input, rather than the companion
/// app alone. Device provisioning and the private clipboard listener still
/// require a real iPhone test after re-signing.
final class KeyboardRegistrationTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testKeyboardCanBeAddedSelectedAndType() throws {
        let environment = ProcessInfo.processInfo.environment
        let appID = try XCTUnwrap(environment["WIANTRIBE_APP_IDENTIFIER"])
        let keyboardName = try XCTUnwrap(environment["WIANTRIBE_KEYBOARD_NAME"])
        let app = XCUIApplication(bundleIdentifier: appID)
        app.launch()
        try tap("Keyboard setup", in: app)
        XCTAssertTrue(app.staticTexts["Keyboard extension included"].waitForExistence(timeout: 8))
        attach("Installed keyboard bundle", app)

        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        try tap("General", in: settings)
        try tap("Keyboard", in: settings)
        // Recent Settings versions also call the page title "Keyboards".
        // Select the row by its identifier so we do not tap that title.
        let keyboardList = settings.buttons["KEYBOARDS"]
        XCTAssertTrue(keyboardList.waitForExistence(timeout: 8), settings.debugDescription)
        keyboardList.tap()
        let add = settings.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Add New Keyboard")).firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 8), settings.debugDescription)
        add.tap()
        try tap(keyboardName, in: settings)
        XCTAssertTrue(settings.navigationBars["Keyboards"].waitForExistence(timeout: 8), settings.debugDescription)
        attach("Keyboard registered in iOS", settings)

        app.activate()
        try tap("Practice", in: app)
        let input = app.textViews["typing-practice"]
        XCTAssertTrue(input.waitForExistence(timeout: 8))
        input.tap()
        let clipboard = app.buttons["Clipboard"]
        for _ in 0..<5 {
            if clipboard.waitForExistence(timeout: 3) { break }
            let globe = app.buttons.matching(NSPredicate(format: "label ==[c] %@", "Next keyboard")).firstMatch
            XCTAssertTrue(globe.waitForExistence(timeout: 5), app.debugDescription)
            globe.tap()
        }
        XCTAssertTrue(clipboard.exists, "WianTribe did not load. \(app.debugDescription)")
        for letter in ["t", "o", "l", "u"] {
            let key = app.buttons.matching(NSPredicate(format: "label ==[c] %@", letter)).firstMatch
            XCTAssertTrue(key.waitForExistence(timeout: 5), app.debugDescription)
            key.tap()
        }
        XCTAssertEqual((input.value as? String)?.lowercased(), "tolu")
        XCTAssertTrue(app.buttons["Space"].exists, "Keyboard was replaced after typing")
        attach("WianTribe typed Tolu", app)
    }

    private func tap(_ label: String, in app: XCUIApplication) throws {
        // Settings rows often expose their label as static text; app controls
        // may expose it as a button or tab. Try exact labels, scrolling as needed.
        for _ in 0..<7 {
            for element in [app.buttons[label].firstMatch, app.staticTexts[label].firstMatch] {
                if element.waitForExistence(timeout: 1), element.isHittable { element.tap(); return }
            }
            app.swipeUp()
        }
        attach("Missing \(label)", app)
        XCTFail("Cannot find \(label). \(app.debugDescription)")
        throw NSError(domain: "KeyboardUITest", code: 1)
    }

    private func attach(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
