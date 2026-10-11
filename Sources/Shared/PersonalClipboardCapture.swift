#if PERSONAL_BACKGROUND_CLIPBOARD
import UIKit
import CoreFoundation

enum PersonalClipboardNotifications {
    static let category = "WianTribeClipboardReader"
    static let changed = "WianTribeClipboardChanged"
    static let stopped = "WianTribeClipboardStopped"
    static let saved = "com.wiantribe.keyboard.personal.clipboardSaved"
    static let didSave = Notification.Name("WianTribePersonalClipboardSaved")
}

enum PersonalClipboardError: LocalizedError {
    case missingSharedStorage, noText, sensitiveCopy, pasteNotAllowed, storageFailure
    var errorDescription: String? {
        switch self {
        case .missingSharedStorage:
            return "Shared clipboard storage is unavailable. Re-sign the app, keyboard and clipboard reader with the same App Group."
        case .noText: return "The current clipboard has no text or web link to save."
        case .sensitiveCopy: return "This copy is marked sensitive and was not saved."
        case .pasteNotAllowed:
            return "iOS did not share the clipboard. Open WianTribe settings and set Paste from Other Apps to Allow, then try again."
        case .storageFailure: return "The clipboard could not be saved. Check available storage and try again."
        }
    }
}

enum PersonalClipboardCapture {
    /// Called only from visible app/notification UI, never from the background listener.
    @MainActor @discardableResult
    static func saveCurrent() throws -> String {
        let store = KeyboardStore()
        guard store.isShared else { throw PersonalClipboardError.missingSharedStorage }
        let pasteboard = UIPasteboard.general
        guard pasteboard.hasStrings else { throw PersonalClipboardError.noText }
        guard let text = pasteboard.string else { throw PersonalClipboardError.pasteNotAllowed }
        guard ClipboardHistory.shouldCapture(text, types: pasteboard.types) else { throw PersonalClipboardError.sensitiveCopy }
        do { try store.captureFromNotification(text) }
        catch { throw PersonalClipboardError.storageFailure }
        store.lastChangeCount = pasteboard.changeCount
        store.clipboardWorked = true
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(PersonalClipboardNotifications.saved as CFString), nil, nil, true)
        NotificationCenter.default.post(name: PersonalClipboardNotifications.didSave, object: nil)
        return "Saved to your WianTribe clipboard"
    }
}
#endif
