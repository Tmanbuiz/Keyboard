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
        let add = settings.buttons["AddNewKeyboard"]
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

        try tap("Show tools", in: app)
        try tap("AI writing assist", in: app)
        for tool in ["Spelling and grammar", "Writing style", "Summarize", "Bullet point", "Table", "Composer"] {
            XCTAssertTrue(app.buttons[tool].exists, "Missing AI menu tool: \(tool)")
        }
        attach("Samsung-style WianTribe writing menu", app)
        try tap("Writing style", in: app)
        XCTAssertTrue(app.buttons["Professional"].exists)
        XCTAssertTrue(app.buttons["Polite"].exists)
        try tap("All writing tools", in: app)
        let provider = app.buttons["writing-provider-menu"]
        XCTAssertTrue(provider.exists); provider.tap()
        try tap("Groq", in: app)
        XCTAssertTrue(app.buttons["AI provider: Groq"].exists)
        attach("Groq selected in the keyboard", app)
        try tap("Spelling and grammar", in: app)
        let accessHint = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Allow Full Access")).firstMatch
        XCTAssertTrue(accessHint.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertEqual((input.value as? String)?.lowercased(), "tolu", "AI must not replace the original without a result and a tap")
        attach("Groq setup requirement shown without replacing text", app)
        try tap("Back to keyboard", in: app)
        XCTAssertTrue(app.buttons["Space"].exists)

        // Enable online access, then use a public dummy key and a Debug/simulator-only
        // result fixture to verify review/edit/replace without a live Groq account.
        settings.activate()
        if !settings.navigationBars["Keyboards"].waitForExistence(timeout: 2) {
            try tap("General", in: settings)
            try tap("Keyboard", in: settings)
            let list = settings.buttons["KEYBOARDS"]
            XCTAssertTrue(list.waitForExistence(timeout: 8), settings.debugDescription)
            list.tap()
        }
        try tap(keyboardName, in: settings)
        let access = settings.switches.firstMatch
        XCTAssertTrue(access.waitForExistence(timeout: 8), settings.debugDescription)
        if access.value as? String == "0" {
            access.tap()
            if settings.alerts.firstMatch.waitForExistence(timeout: 2) { settings.alerts.buttons["Allow"].tap() }
        }
        app.activate()
        if app.buttons["Dismiss keyboard"].waitForExistence(timeout: 2) { app.buttons["Dismiss keyboard"].tap() }
        try tap("Tools", in: app)
        try tap("AI setup", in: app)
        let keyField = app.secureTextFields["groq-api-key"]
        XCTAssertTrue(keyField.waitForExistence(timeout: 8)); keyField.tap()
        keyField.typeText("gsk_WIANTRIBE_UI_TEST_ONLY")
        try tap("Save Groq and use it", in: app)
        try tap("Copy AI connection for keyboard", in: app)
        try tap("Practice", in: app)
        input.tap()
        for _ in 0..<5 {
            if app.buttons["Clipboard"].waitForExistence(timeout: 2) || app.buttons["Show tools"].exists { break }
            let globe = app.buttons.matching(NSPredicate(format: "label ==[c] %@", "Next keyboard")).firstMatch
            XCTAssertTrue(globe.waitForExistence(timeout: 5)); globe.tap()
        }
        if app.buttons["Show tools"].exists { app.buttons["Show tools"].tap() }
        try tap("AI writing assist", in: app)
        app.buttons["writing-provider-menu"].tap()
        try tap("Import AI connection", in: app)
        if app.alerts.firstMatch.waitForExistence(timeout: 2), app.alerts.buttons["Allow Paste"].exists { app.alerts.buttons["Allow Paste"].tap() }
        XCTAssertTrue(app.buttons["AI provider: Groq"].waitForExistence(timeout: 8))
        try tap("Spelling and grammar", in: app)
        XCTAssertTrue(app.staticTexts["writing-result"].waitForExistence(timeout: 8), app.debugDescription)
        for action in ["Edit", "Copy", "Replace"] { XCTAssertTrue(app.buttons[action].exists) }
        XCTAssertEqual((input.value as? String)?.lowercased(), "tolu")
        attach("AI result card with Edit Copy Replace", app)
        try tap("Edit", in: app)
        try tap("Space", in: app)
        for letter in ["g", "o", "o", "d"] {
            let key = app.buttons.matching(NSPredicate(format: "label ==[c] %@", letter)).firstMatch
            XCTAssertTrue(key.exists); key.tap()
        }
        XCTAssertEqual((input.value as? String)?.lowercased(), "tolu", "Editing the preview changed the host app")
        attach("Editing AI result independently of the original", app)
        try tap("Done", in: app)
        try tap("Replace", in: app)
        XCTAssertEqual((input.value as? String)?.lowercased(), "tolu. good")
        XCTAssertTrue(app.buttons["Space"].exists)
        attach("AI result inserted only after Replace", app)
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
