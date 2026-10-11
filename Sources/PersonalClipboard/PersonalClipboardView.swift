#if PERSONAL_BACKGROUND_CLIPBOARD
import SwiftUI
import UIKit

@MainActor
struct PersonalClipboardSection: View {
    @ObservedObject private var monitor = PersonalClipboardMonitor.shared
    var body: some View {
        Section {
            Toggle("Monitor copy changes", isOn: Binding(
                get: { monitor.enabled }, set: { monitor.setEnabled($0) }
            )).disabled(monitor.busy)
            if monitor.busy { ProgressView("Checking permissions…") }
            Label(monitor.status, systemImage: monitor.running ? "checkmark.circle" : "info.circle")
                .font(.caption).foregroundStyle(monitor.running ? Color.mint : Color.orange)
            if monitor.enabled {
                Button("Check and resume monitoring") { monitor.resume() }.disabled(monitor.busy)
            }
            Button("Open permission settings", systemImage: "gearshape") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            Text("Copy in any app, then touch and hold the “Clipboard changed” notification to save the current text. Opening the notification normally also saves it in the app.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Each saved copy appears in your keyboard’s 📋 panel. Enable Allow Full Access for clipboard controls there.")
                .font(.caption).foregroundStyle(.secondary)
            if monitor.changeEvents > 0 {
                LabeledContent("Copy events this session", value: "\(monitor.changeEvents)").font(.caption)
            }
        } header: { Text("Personal clipboard monitor") } footer: {
            Text("Based on Clipper. Needs notifications, Location set to Always, and shared App Group signing. Location keeps this personal monitor running; coordinates are never saved or sent. Background location can affect battery use. If iOS ends the app, reopen it to resume.")
        }
    }
}
#endif
