import SwiftUI

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
    @Published var preferences: KeyboardPreferences { didSet { store.preferences = preferences } }
    @Published var phrases: [SavedPhrase] { didSet { store.phrases = phrases } }
    var shared: Bool { store.isShared }
    init() { preferences = store.preferences; phrases = store.phrases }
    func reload() { preferences = store.preferences; phrases = store.phrases }
    func savePhrase(_ text: String) { store.addPhrase(text); phrases = store.phrases }
    func clearPersonalData() { store.clearPersonalData(); phrases = [] }
    func clearLearnedWords() { store.learned = [:]; store.learnedPairs = [:] }
    func clearRecentClips() { store.clearRecentClips(); phrases = store.phrases }
}
