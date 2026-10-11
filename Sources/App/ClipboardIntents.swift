import AppIntents
import UIKit

/// "Save Clipboard to WianTribe": an action for Shortcuts, Siri, Spotlight, the Action button,
/// Back Tap and Control Center. It runs only when the person triggers it, so it follows
/// App Store rules while letting them save a copy without opening the keyboard.
struct SaveClipboardIntent: AppIntent {
    static var title: LocalizedStringResource = "Save Clipboard to WianTribe"
    static var description = IntentDescription("Adds what you copied to your WianTribe keyboard clipboard, so you can paste it later from the keyboard.")
    static var openAppWhenRun = false

    @Parameter(title: "Text", description: "Leave empty to save what's on the clipboard now.")
    var text: String?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let pasteboard = UIPasteboard.general
        let value: String?
        var types: [String] = []
        if let text, !text.isEmpty { value = text } else {
            guard pasteboard.hasStrings else { return .result(dialog: "There's no text on the clipboard. Copy something first.") }
            value = pasteboard.string
            types = pasteboard.types
            guard value != nil else {
                return .result(dialog: "iOS didn't share the clipboard. In Settings → Apps → WianTribe Keyboard, set Paste from Other Apps to Allow.")
            }
        }
        guard let value, ClipboardHistory.shouldCapture(value, types: types) else {
            return .result(dialog: "That can't be saved. Copies from password managers are skipped.")
        }
        let store = KeyboardStore()
        store.capture(value)
        if types.isEmpty == false { store.lastChangeCount = pasteboard.changeCount }
        return .result(dialog: "Saved to WianTribe")
    }
}

struct WianTribeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: SaveClipboardIntent(),
                    phrases: ["Save clipboard to \(.applicationName)", "Save to \(.applicationName)", "Save my copy in \(.applicationName)"],
                    shortTitle: "Save Clipboard",
                    systemImageName: "doc.on.clipboard")
    }
}
