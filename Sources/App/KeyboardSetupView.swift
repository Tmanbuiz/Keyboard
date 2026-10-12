import SwiftUI
import UIKit

/// Examines the installed bundle, including any changes made by a sideloader.
/// Finding a bundle does not prove iOS registered or enabled the extension.
private struct KeyboardInstallation {
    let appName: String
    let appID: String
    let keyboard: Bundle?
    let executablePresent: Bool
    let identifierMatches: Bool
    let sharedClipboard: Bool
    let signingReport: String

    init() {
        appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "WianTribe Keyboard"
        appID = Bundle.main.bundleIdentifier ?? "unknown"
        let folders = Bundle.main.builtInPlugInsURL.flatMap {
            try? FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil)
        } ?? []
        keyboard = folders.compactMap { Bundle(url: $0) }.first {
            ($0.infoDictionary?["NSExtension"] as? [String: Any])?["NSExtensionPointIdentifier"] as? String == "com.apple.keyboard-service"
        }
        if let keyboard, let name = keyboard.object(forInfoDictionaryKey: "CFBundleExecutable") as? String {
            executablePresent = FileManager.default.fileExists(atPath: keyboard.bundleURL.appendingPathComponent(name).path)
        } else { executablePresent = false }
        identifierMatches = keyboard?.bundleIdentifier?.hasPrefix(appID + ".") == true
        sharedClipboard = KeyboardStore().isShared
        signingReport = keyboard.map { SigningInspection.inspect($0) } ?? "Keyboard missing"
    }

    var report: String {
        let extensionInfo = keyboard?.infoDictionary?["NSExtension"] as? [String: Any]
        let attributes = extensionInfo?["NSExtensionAttributes"] as? [String: Any]
        return """
        WianTribe installation details
        App: \(appName)
        Version: \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"))
        iOS: \(UIDevice.current.systemVersion)
        App identifier: \(appID)
        Keyboard included: \(keyboard != nil)
        Keyboard executable included: \(executablePresent)
        Keyboard identifier: \(keyboard?.bundleIdentifier ?? "missing")
        Keyboard identifier has app prefix: \(identifierMatches)
        Keyboard language: \(attributes?["PrimaryLanguage"] as? String ?? "missing")
        Principal class: \(extensionInfo?["NSExtensionPrincipalClass"] as? String ?? "missing")
        Shared clipboard available in app: \(sharedClipboard)
        App group: \(KeyboardStore.appGroup)
        Bundle checks do not verify iOS registration, keyboard enablement or Full Access.

        Installed keyboard signing check:
        \(signingReport)
        """
    }
}

struct KeyboardSetupView: View {
    @State private var installation = KeyboardInstallation()

    var body: some View {
        List {
            Section("Add the keyboard") {
                Text("Open the iPhone’s Settings app, then follow these steps:")
                Label("General → Keyboard → Keyboards", systemImage: "1.circle")
                Label("Add New Keyboard → \(installation.appName)", systemImage: "2.circle")
                Label("Open a text box and hold 🌐 to select \(installation.appName)", systemImage: "3.circle")
                Text("The app’s permission page, which shows Cellular Data, is a different screen. Return to the main Settings page to find General.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Check this installation") {
                Label(installation.keyboard != nil ? "Keyboard extension included" : "Keyboard extension missing",
                      systemImage: installation.keyboard != nil ? "checkmark.circle" : "exclamationmark.triangle")
                    .foregroundStyle(installation.keyboard != nil ? Color.mint : Color.orange)
                    .accessibilityIdentifier("keyboard-bundle-check")
                if installation.keyboard == nil || !installation.executablePresent {
                    Text("Reinstall the IPA with the keyboard extension kept. In Sideloadly, the plug-ins control should say “Dropping 0”.")
                } else if !installation.identifierMatches {
                    Text("The installer changed the app and keyboard identifiers inconsistently. Reinstall with matching identifiers for the app and its extensions.")
                } else {
                    Text("The keyboard files are present. If it is absent from Add New Keyboard, share the installation details and the installer log so its registration can be checked.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button("Check again") { installation = KeyboardInstallation() }
                ShareLink(item: installation.report) { Label("Share installation details", systemImage: "square.and.arrow.up") }
            }
            Section("Installed signature") {
                Text(installation.signingReport).font(.caption).textSelection(.enabled)
                Text("If the keyboard returns to Apple’s keyboard, share installation details so the installed signature can be compared with the crash report.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Clipboard permissions") {
                Text("After adding the keyboard, tap its name under Keyboards and enable Allow Full Access for clipboard controls.")
                Label(installation.sharedClipboard ? "Shared clipboard available" : "Shared clipboard unavailable",
                      systemImage: installation.sharedClipboard ? "checkmark.circle" : "info.circle")
                if !installation.sharedClipboard {
                    Text("The installer must sign the app, keyboard and notification reader with access to the same shared storage. Basic typing works separately from this capability.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button("Open app permissions", systemImage: "gearshape") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                Text("App permissions is where you manage notifications and location for the personal clipboard monitor.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Keyboard setup")
        .navigationBarTitleDisplayMode(.inline)
    }
}
