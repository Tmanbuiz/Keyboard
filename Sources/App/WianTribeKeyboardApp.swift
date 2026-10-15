import SwiftUI
import UIKit

@main
struct WianTribeKeyboardApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(model)
                .tint(Color.mint)
                .preferredColorScheme(.dark)
                .onChange(of: scenePhase) { _, phase in if phase == .active { model.reload() } }
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    private let store = KeyboardStore()
    @Published var clipboardStatus = ""
    @Published var preferences: KeyboardPreferences { didSet { store.preferences = preferences } }
    @Published var phrases: [SavedPhrase] { didSet { store.phrases = phrases } }
    var shared: Bool { store.isShared }
    init() { preferences = store.preferences; phrases = store.phrases }
    func reload() {
        preferences = store.preferences
        captureClipboardOnOpen()
        phrases = store.phrases
    }
    /// With clipboard history on, opening the app saves the latest copy, like the keyboard does.
    func captureClipboardOnOpen() {
        guard preferences.clipboardHistory, !preferences.privateMode else { return }
        let pasteboard = UIPasteboard.general
        guard pasteboard.changeCount != store.lastChangeCount, pasteboard.hasStrings else { return }
        guard let text = pasteboard.string else { return }
        store.lastChangeCount = pasteboard.changeCount
        guard ClipboardHistory.shouldCapture(text, types: pasteboard.types) else {
            clipboardStatus = "Copy skipped: sensitive, empty or over 5,000 characters."; return
        }
        store.capture(text)
    }
    /// From Apple's Paste button, which never shows the "Allow Paste" question.
    func saveClip(_ text: String) {
        guard !preferences.privateMode else { clipboardStatus = "Private typing is on. Turn it off to save clipboard entries."; return }
        guard ClipboardHistory.shouldCapture(text) else { clipboardStatus = "Nothing saved: use 1–5,000 characters."; return }
        store.capture(text); phrases = store.phrases; clipboardStatus = "Saved"
    }
    func savePhrase(_ text: String) { store.addPhrase(text); phrases = store.phrases }
    func clearPersonalData() { store.clearPersonalData(); phrases = [] }
    func clearLearnedWords() { store.learned = [:]; store.learnedPairs = [:] }
    /// Reading the clipboard here makes iOS show its paste prompt and adds "Paste from Other Apps"
    /// to this app's page in Settings, which also covers the keyboard.
    func testClipboard() -> String {
        let pasteboard = UIPasteboard.general
        guard pasteboard.hasStrings else { return "Copy some text in another app first, then tap Test again." }
        guard let text = pasteboard.string else { return "iOS didn't share the clipboard. Tap Open WianTribe settings and set Paste from Other Apps to Allow." }
        return "Clipboard access works (\(text.count) characters). Now copy text anywhere and open 📋 on the keyboard."
    }
    func clearRecentClips() { store.clearRecentClips(); phrases = store.phrases }
}
