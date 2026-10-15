import SwiftUI
import UIKit

private let ocean = Color(red: 0.035, green: 0.10, blue: 0.13)
private let card = Color(red: 0.07, green: 0.17, blue: 0.20)

struct ContentView: View {
    var body: some View {
        TabView {
            NavigationStack { HomeView() }.tabItem { Label("Home", systemImage: "keyboard") }
            NavigationStack { PracticeView() }.tabItem { Label("Practice", systemImage: "text.cursor") }
            NavigationStack { ToolsView() }.tabItem { Label("Tools", systemImage: "square.grid.2x2") }
            NavigationStack { SettingsView() }.tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
        }
        .toolbarBackground(ocean, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}

private struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                HStack(spacing: 9) {
                    Image(systemName: "keyboard.fill").foregroundStyle(.mint)
                    Text("WIANTRIBE").font(.caption.weight(.semibold)).tracking(3)
                    Spacer()
                    Text("KEYBOARD").font(.caption2).foregroundStyle(.secondary)
                }.padding(.top, 14)
                Text("Your words.\nYour way.")
                    .font(.system(size: 45, weight: .bold, design: .rounded)).tracking(-1.5)
                Text("A little more you, in every message.")
                    .font(.subheadline).foregroundStyle(.secondary)
                LayoutPreview(theme: model.preferences.theme, numberRow: model.preferences.numberRow)
                    .accessibilityLabel("Keyboard layout preview")
                VStack(alignment: .leading, spacing: 16) {
                    Text("Let's get you typing").font(.title3.weight(.semibold))
                    setupStep("1", title: "Add WianTribe Keyboard", detail: "Open Settings → General → Keyboard → Keyboards → Add New Keyboard → WianTribe.")
                    setupStep("2", title: "Switch with the globe", detail: "Open a message, hold 🌐, then choose WianTribe Keyboard.")
                    setupStep("3", title: "Make it yours", detail: "Tap ⚙︎ on the keyboard to choose your theme, layout and language.")
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    } label: { Label("Open Settings", systemImage: "gearshape").frame(maxWidth: .infinity).padding(.vertical, 8) }
                        .buttonStyle(.borderedProminent).tint(.mint).foregroundStyle(ocean)
                    Text("Typing works offline without Full Access. Enable Allow Full Access only for clipboard history, media copying and optional online writing tools.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(20).background(card, in: RoundedRectangle(cornerRadius: 22))
                HStack(alignment: .top, spacing: 20) {
                    feature("wifi.slash", "Offline first")
                    feature("globe", "\(LanguageCatalog.all.count) languages")
                    feature("hand.draw", "Swipe to type")
                }.frame(maxWidth: .infinity)
                Text("Independent software by WianTribe. Samsung's branding and assets are not used.")
                    .font(.caption2).foregroundStyle(.secondary)
            }.padding(22)
        }
        .background(ocean).toolbar(.hidden, for: .navigationBar)
    }
    private func setupStep(_ number: String, title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number).font(.caption.weight(.bold)).frame(width: 26, height: 26)
                .background(Color.mint.opacity(0.15), in: Circle()).foregroundStyle(.mint)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private func feature(_ icon: String, _ title: LocalizedStringKey) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.title3).foregroundStyle(.mint)
            Text(title).font(.caption2.weight(.medium))
        }.frame(maxWidth: .infinity)
    }
}

struct LayoutPreview: View {
    var theme: KeyboardTheme
    var numberRow: Bool
    @Environment(\.colorScheme) private var scheme
    private var light: Bool { theme == .light || (theme == .auto && scheme == .light) }
    private var base: Color {
        switch theme {
        case .auto: return light ? Color(white: 0.85) : Color(white: 0.10)
        case .ocean: return card; case .midnight: return Color(white: 0.10); case .light: return Color(white: 0.85)
        case .rose: return Color(red: 0.22, green: 0.10, blue: 0.16); case .forest: return Color(red: 0.08, green: 0.15, blue: 0.10)
        case .sunset: return Color(red: 0.24, green: 0.11, blue: 0.08); case .slate: return Color(red: 0.13, green: 0.15, blue: 0.19)
        }
    }
    var body: some View {
        VStack(spacing: 6) {
            HStack { Text("Layout preview"); Spacer(); Image(systemName: "sparkle") }
                .font(.caption2).foregroundStyle(light ? Color.black.opacity(0.6) : Color.mint).padding(.bottom, 5)
            // The tool row as it appears on the keyboard when you aren't typing.
            HStack {
                Text("EN").font(.caption.weight(.semibold))
                ForEach(["face.smiling", "doc.on.clipboard", "sparkles", "translate", "pencil.and.scribble", "character.cursor.ibeam", "gearshape"], id: \.self) { symbol in
                    Spacer(minLength: 0); Image(systemName: symbol).font(.system(size: 15))
                }
            }.padding(.horizontal, 10).padding(.bottom, 6)
                .accessibilityLabel("Tools: emoji, clipboard, AI writing, translate, handwriting, text editing, settings")
            if numberRow { keyRow("1234567890", size: 11) }
            keyRow("qwertyuiop", size: 16)
            keyRow("asdfghjkl", size: 16).padding(.horizontal, 12)
            HStack(spacing: 5) {
                previewKey("⇧", size: 17).frame(width: 31)
                keyRow("zxcvbnm", size: 16)
                previewKey("⌫", size: 17).frame(width: 31)
            }
            HStack(spacing: 5) {
                previewKey("123", size: 11).frame(width: 34)
                previewKey("🌐", size: 12).frame(width: 30)
                previewKey("English", size: 11)
                previewKey("↵", size: 18).frame(width: 42)
            }
        }.foregroundStyle(light ? Color.black : Color.white).padding(13).background(base, in: RoundedRectangle(cornerRadius: 18))
    }
    private func keyRow(_ letters: String, size: CGFloat) -> some View {
        HStack(spacing: 5) { ForEach(Array(letters.enumerated()), id: \.offset) { _, letter in previewKey(String(letter), size: size) } }
    }
    private func previewKey(_ text: String, size: CGFloat) -> some View {
        Text(text).font(.system(size: size)).frame(maxWidth: .infinity).frame(height: 31)
            .background(light ? Color.white : Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 5))
    }
}

private struct PracticeView: View {
    @State private var text = ""
    @State private var copied = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Try your new keyboard").font(.title.bold())
                Text("Tap the box, then hold the globe key to select WianTribe.").foregroundStyle(.secondary)
                TextEditor(text: $text).frame(height: 210).scrollContentBackground(.hidden)
                    .padding(10).background(card, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty { Text("Type something here…").foregroundStyle(.secondary).padding(18).allowsHitTesting(false) }
                    }
                    .accessibilityLabel("Typing practice")
                HStack {
                    Button(copied ? "Copied" : "Copy text", systemImage: "doc.on.doc") { UIPasteboard.general.string = text; copied = true }
                        .buttonStyle(.bordered).disabled(text.isEmpty)
                    Spacer()
                    Button("Clear", role: .destructive) { text = ""; copied = false }
                }
                VStack(alignment: .leading, spacing: 13) {
                    tip("hand.draw", "Swipe from h → e → l → o to write hello.")
                    tip("character.cursor.ibeam", "Drag the space bar left or right to move your cursor.")
                    tip("character", "Hold e, o or s for ẹ, ọ and ṣ. Hold vowels for tone marks.")
                    tip("arrow.uturn.backward", "After an autocorrection, tap the original word or press delete to undo it.")
                    tip("globe", "Tap EN / YO / NG on the keyboard to change language.")
                }.padding(18).background(card, in: RoundedRectangle(cornerRadius: 16))
                Text("Suggestions, autocorrect and swipe use dictionaries for each of your languages. Password fields and some apps use Apple's keyboard.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(22)
        }.background(ocean).navigationTitle("Practice").navigationBarTitleDisplayMode(.inline)
            .onChange(of: text) { _, _ in copied = false }
    }
    private func tip(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) { Image(systemName: icon).foregroundStyle(.mint).frame(width: 22); Text(text).font(.subheadline) }
    }
}

private struct ToolsView: View {
    var body: some View {
        List {
            Section {
                NavigationLink { AIAccountView() } label: { tool("person.crop.circle", "AI account", "Sign in once to connect your keyboard") }
                NavigationLink { VoiceView() } label: { tool("waveform", "Voice editor", "Speak, review and copy your transcript") }
                NavigationLink { WriterView() } label: { tool("sparkles", "Writing assistant", "Grammar, tone and translation with WianTribe AI") }
                NavigationLink { PhrasesView() } label: { tool("doc.on.clipboard", "Clipboard", "Recent copies and pinned text") }
                NavigationLink { TranslationLanguagesView() } label: { tool("globe", "Translation languages", "Download languages for on-device translation") }
            }
            Section {
                Text("Typing, emoji, stickers and your clipboard work offline. Translation and rewriting run on your iPhone where Apple supports them; WianTribe AI covers other languages and GIF search.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }.scrollContentBackground(.hidden).background(ocean).navigationTitle("Your toolkit")
    }
    private func tool(_ icon: String, _ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon).font(.title2).foregroundStyle(.mint).frame(width: 32)
            VStack(alignment: .leading, spacing: 5) { Text(title).font(.headline); Text(detail).font(.caption).foregroundStyle(.secondary) }.padding(.vertical, 10)
        }
    }
}

private struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var clearData = false
    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $model.preferences.theme) { ForEach(KeyboardTheme.allCases) { Text($0.title).tag($0) } }
                LayoutPreview(theme: model.preferences.theme, numberRow: model.preferences.numberRow).listRowInsets(EdgeInsets())
                Picker("Accent colour", selection: $model.preferences.accent) { ForEach(KeyAccent.allCases) { Text($0.title).tag($0) } }
                Toggle("Key outlines", isOn: $model.preferences.keyBorders)
                Toggle("Number row", isOn: $model.preferences.numberRow)
                Picker("Layout", selection: $model.preferences.handMode) { ForEach(HandMode.allCases) { Text($0.title).tag($0) } }
                HStack { Text("Height"); Slider(value: $model.preferences.height, in: 240...360, step: 30); Text("\(Int(model.preferences.height))").monospacedDigit() }
            }
            Section("Typing") {
                NavigationLink { LanguagesView() } label: {
                    LabeledContent("Languages", value: model.preferences.activeLanguages.map(\.shortTitle).joined(separator: " · "))
                }
                Toggle("Autocorrect", isOn: $model.preferences.autocorrect)
                Toggle("Word suggestions", isOn: $model.preferences.predictions)
                Toggle("Emoji suggestions", isOn: $model.preferences.emojiPredictions)
                Toggle("Swipe typing", isOn: $model.preferences.swipeTyping)
                Toggle("Auto capitals", isOn: $model.preferences.autoCapitalization)
                Toggle("Double-space period", isOn: $model.preferences.doubleSpacePeriod)
                Toggle("Haptic feedback", isOn: $model.preferences.haptics)
                Toggle("Key sounds", isOn: $model.preferences.keySounds)
                Toggle("Key pop-up preview", isOn: $model.preferences.keyPreview)
            }
            Section {
                Picker("AI engine", selection: $model.preferences.aiEngine) { ForEach(AIEngine.allCases) { Text($0.title).tag($0) } }
            } header: { Text("AI writing") } footer: {
                Text("Choose “My own AI service only” to send writing tools and translation to the service you connect in Tools → Writing assistant, instead of Apple's on-device models. The keyboard has the same switch under ⚙︎.")
            }
            Section {
                Toggle("Clipboard history", isOn: $model.preferences.clipboardHistory)
                Picker("Keep recent clips", selection: $model.preferences.clipboardDays) {
                    ForEach(ClipboardHistory.dayOptions, id: \.self) { Text("\($0) day\($0 == 1 ? "" : "s")").tag($0) }
                }
            } header: { Text("Clipboard") } footer: {
                Text("Needs Allow Full Access. While the keyboard is open, it keeps text you copy so you can paste it anywhere. Pinned items never expire. Copies from password managers are skipped, and nothing leaves this iPhone.")
            }
            Section {
                Toggle("Private typing", isOn: $model.preferences.privateMode)
                Text("Pauses automatic clipboard capture and word learning. Saved items remain available. Explicit AI requests still use the engine you selected.").font(.caption).foregroundStyle(.secondary)
                NavigationLink("TestFlight feedback") { TesterFeedbackView() }
                Toggle("Learn my words on this device", isOn: $model.preferences.learnWords)
                Button("Clear learned words", role: .destructive) { model.clearLearnedWords() }
                NavigationLink("Privacy & iOS limits") { PrivacyView() }
                Button("Clear clipboard, pinned text and learned words", role: .destructive) { clearData = true }
            } header: { Text("Privacy") } footer: {
                Text("Word learning is off by default. It saves word counts, not sentences. Remove personal data inside the keyboard too if your build uses separate storage.")
            }
            Section {
                Text(model.shared ? "App and keyboard share settings when Full Access is enabled." : "This sideloaded build keeps app and keyboard settings separate. Tap ⚙︎ inside the keyboard to change the keyboard itself.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("WianTribe Keyboard \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")").font(.caption).foregroundStyle(.secondary)
            }
        }.scrollContentBackground(.hidden).background(ocean).navigationTitle("Make it yours")
            .confirmationDialog("Clear clipboard history, pinned text and learned words on this device?", isPresented: $clearData) {
                Button("Clear personal data", role: .destructive) { model.clearPersonalData() }
            }
    }
}

/// Keyboards can't ask iOS to download translation languages, so the app does it.
private struct TranslationLanguagesView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        List {
            Section {
                Text("Translation in the keyboard runs on your iPhone with Apple's Translate models. Download each language once here; after that it works offline.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if #available(iOS 18.0, *) {
                Section("Your languages") {
                    ForEach(model.preferences.activeLanguages + (model.preferences.activeLanguages.contains(.english) ? [] : [.english])) { language in
                        TranslationDownloadRow(language: language)
                    }
                }
            } else {
                Section { Text("On-device translation needs iOS 18 or later.").foregroundStyle(.secondary) }
            }
        }.scrollContentBackground(.hidden).background(ocean).navigationTitle("Translation languages")
    }
}

#if canImport(Translation)
import Translation

@available(iOS 18.0, *)
private struct TranslationDownloadRow: View {
    let language: KeyboardLanguage
    @State private var status = ""
    @State private var configuration: TranslationSession.Configuration?
    private var target: Locale.Language { Locale.Language(identifier: language.pack.primaryLanguage) }
    private var source: Locale.Language { Locale.Language(identifier: language.code == "en" ? (Locale.current.language.languageCode?.identifier ?? "fr") : "en") }
    var body: some View {
        HStack {
            VStack(alignment: .leading) { Text(language.title); Text(status).font(.caption).foregroundStyle(.secondary) }
            Spacer()
            Button("Download") { configuration = .init(source: source, target: target) }.buttonStyle(.bordered)
                .disabled(status == "Ready" || status == "Not available")
        }
        .task { await refresh() }
        .translationTask(configuration) { session in
            do { try await session.prepareTranslation(); await refresh() }
            catch { status = "Download didn't finish" }
        }
    }
    private func refresh() async {
        switch await LanguageAvailability().status(from: source, to: target) {
        case .installed: status = "Ready"
        case .supported: status = "Not downloaded yet"
        default: status = "Not available"
        }
    }
}
#else
private struct TranslationDownloadRow: View {
    let language: KeyboardLanguage
    var body: some View { Text(language.title) }
}
#endif

private struct LanguagesView: View {
    @EnvironmentObject private var model: AppModel
    private var enabled: [KeyboardLanguage] { model.preferences.activeLanguages }
    var body: some View {
        List {
            Section {
                Toggle("Multilingual typing", isOn: $model.preferences.multilingual)
            } footer: { Text("Suggestions and swipe draw on all your languages that share an alphabet, so you can mix them in one message without switching.") }
            Section("Your languages") {
                ForEach(enabled) { language in
                    HStack {
                        VStack(alignment: .leading) { Text(language.title); Text(language.pack.englishName).font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        if language == model.preferences.language { Text("Current").font(.caption).foregroundStyle(.mint) }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { model.preferences.language = language }
                    .swipeActions {
                        if language != model.preferences.language {
                            Button("Remove", role: .destructive) { model.preferences.languages = enabled.filter { $0 != language } }
                        }
                    }
                }
            }
            Section("Add a language") {
                ForEach(LanguageCatalog.all.filter { pack in !enabled.contains { $0.code == pack.code } }.sorted { $0.englishName < $1.englishName }) { pack in
                    Button {
                        guard enabled.count < 6 else { return }
                        model.preferences.languages = enabled + [KeyboardLanguage(pack.code)]
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(pack.name).foregroundStyle(.primary)
                                Text(pack.englishName + (pack.hasDictionary ? "" : " · layout and accents only")).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(); Image(systemName: "plus.circle")
                        }
                    }.disabled(enabled.count >= 6)
                }
            }
            Section { Text("Word lists from wordfreq by Robyn Speer (CC BY-SA 4.0). Yorùbá and Naija Pidgin lists by WianTribe. Up to 6 languages.").font(.caption).foregroundStyle(.secondary) }
        }.scrollContentBackground(.hidden).background(ocean).navigationTitle("Languages")
    }
}

private struct PhrasesView: View {
    @EnvironmentObject private var model: AppModel
    @State private var draft = ""
    @State private var clipboardTest = ""
    @State private var query = ""
    @State private var pinnedOnly = false
    @State private var folder = ""
    var body: some View {
        List {
            Section("Pin a phrase") {
                TextField("Write or paste text to keep", text: $draft, axis: .vertical).lineLimit(2...5)
                Button("Pin", systemImage: "pin") { model.savePhrase(draft); draft = "" }.disabled(!ClipboardHistory.shouldCapture(draft))
                Text("Each saved entry can contain up to \(ClipboardHistory.maxLength) characters. Longer entries are rejected without truncation.").font(.caption).foregroundStyle(.secondary)
                Text("Pinned text never expires. Recent copies are kept for \(model.preferences.clipboardDays) day\(model.preferences.clipboardDays == 1 ? "" : "s"), up to \(ClipboardHistory.maxRecent) items.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Clipboard") {
                Toggle("Pinned only", isOn: $pinnedOnly)
                Picker("Folder", selection: $folder) {
                    Text("All folders").tag("")
                    ForEach(Array(Set(model.phrases.compactMap(\.folder).filter { !$0.isEmpty })).sorted(), id: \.self) { Text($0).tag($0) }
                }
                PasteButton(payloadType: String.self) { strings in
                    let text = strings.joined(separator: "\n")
                    DispatchQueue.main.async { model.saveClip(text) }
                }.labelStyle(.titleAndIcon)
                if !model.clipboardStatus.isEmpty { Text(model.clipboardStatus).font(.caption) }
                if model.phrases.isEmpty { Text("Copied and pinned text will appear here.").foregroundStyle(.secondary) }
                ForEach(ClipboardHistory.ordered(model.phrases).filter { (!pinnedOnly || $0.pinned) && (folder.isEmpty || $0.folder == folder) && (query.isEmpty || $0.text.localizedCaseInsensitiveContains(query)) }) { phrase in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(phrase.text).lineLimit(6)
                        TextField("Folder (optional)", text: Binding(
                            get: { model.phrases.first { $0.id == phrase.id }?.folder ?? "" },
                            set: { value in
                                if let i = model.phrases.firstIndex(where: { $0.id == phrase.id }) {
                                    model.phrases[i].folder = String(value.prefix(40))
                                }
                            })).font(.caption)
                        HStack {
                            Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = phrase.text }
                            Spacer()
                            Button(phrase.pinned ? "Unpin" : "Pin", systemImage: "pin") {
                                if let i = model.phrases.firstIndex(where: { $0.id == phrase.id }) { model.phrases[i].pinned.toggle() }
                            }
                        }.font(.caption).buttonStyle(.borderless)
                    }.padding(.vertical, 5)
                        .swipeActions { Button("Delete", role: .destructive) { model.phrases.removeAll { $0.id == phrase.id } } }
                }
            }
            Section {
                Label("Back Tap: double-tap the back of your iPhone", systemImage: "hand.tap")
                Text("1. Open Shortcuts, tap +, add the action Save Clipboard to WianTribe, and save it.\n2. Settings → Accessibility → Touch → Back Tap → Double Tap → choose that shortcut.\nNow copy anything, double-tap the back of the phone, and it's in your keyboard clipboard.")
                    .font(.caption).foregroundStyle(.secondary)
                Label("Share: Save to WianTribe", systemImage: "square.and.arrow.up")
                Text("Select text or a link in any app, tap Share, then Save to WianTribe. If you don't see it, tap More (…) and turn it on.")
                    .font(.caption).foregroundStyle(.secondary)
                Label("Action button, Control Center or Siri", systemImage: "button.programmable")
                Text("Assign the same shortcut to the Action button or a Control Center shortcut, or say “Save clipboard to WianTribe”.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Open Shortcuts", systemImage: "square.2.layers.3d") {
                    if let url = URL(string: "shortcuts://") { UIApplication.shared.open(url) }
                }
            } header: { Text("Save copies without opening the keyboard") } footer: {
                Text(model.shared ? "Everything you save here appears in the keyboard's 📋 straight away." : "This sideloaded build keeps the app's and keyboard's clipboards separate. The App Store version shares them, so everything saved here appears in the keyboard.")
            }
            if model.phrases.contains(where: { !$0.pinned }) {
                Section { Button("Clear recent clips", role: .destructive) { model.clearRecentClips() } }
            }
            Section {
                Text("iOS asks before an app reads what you copied, but a keyboard can't show that question, so set Paste from Other Apps to Allow. The keyboard then keeps what you copy while it's open.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Test clipboard access", systemImage: "checkmark.shield") { clipboardTest = model.testClipboard() }
                if !clipboardTest.isEmpty { Text(clipboardTest).font(.caption) }
                Button("Open WianTribe settings", systemImage: "gearshape") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            } header: { Text("Set up clipboard access") } footer: {
                Text("In Settings: Paste from Other Apps → Allow. Also turn on clipboard history inside the keyboard: 📋 → Turn on clipboard history.")
            }
        }.searchable(text: $query, prompt: "Search saved text")
        .scrollContentBackground(.hidden).background(ocean).navigationTitle("Clipboard")
    }
}

private struct WriterView: View {
    @State private var text = ""
    @State private var result = ""
    @State private var language: KeyboardLanguage = LanguageCatalog.deviceLanguages().first ?? .english
    @State private var status = ""
    @State private var busy = false
    @State private var request: Task<Void, Never>?
    var body: some View {
        Form {
            Section("Your text") {
                TextEditor(text: $text).frame(minHeight: 130).accessibilityLabel("Text for writing assistant")
                Picker("Translation language", selection: $language) { ForEach(KeyboardLanguage.allCases) { Text($0.title).tag($0) } }
                ForEach(WritingAction.allCases) { action in
                    Button(action == .translate ? "Translate to \(language.title)" : action.title) { perform(action) }
                        .disabled(busy || text.isEmpty)
                }
                Text("Runs on this iPhone when Apple supports the language. Otherwise only the text above is sent to your service. Review results before using them.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if busy { Section { ProgressView("Working…") } }
            if !status.isEmpty { Section { Text(status).font(.caption) } }
            if !result.isEmpty {
                Section("Review result") {
                    TextEditor(text: $result).frame(minHeight: 150).accessibilityLabel("Edit AI result")
                    Button("Copy result", systemImage: "doc.on.doc") { UIPasteboard.general.string = result; status = "Result copied" }
                    Button("Use as input") { text = result; result = "" }
                }
            }
            Section("WianTribe AI") {
                NavigationLink("AI account") { AIAccountView() }
                Text("Sign in with Apple once. The keyboard connects automatically on this iPhone.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.scrollContentBackground(.hidden).background(ocean).navigationTitle("Writing assistant")
            .onDisappear { request?.cancel() }
    }
    private func perform(_ action: WritingAction) {
        busy = true; status = ""; result = ""
        request = Task { @MainActor in
            defer { busy = false }
            do {
                // Apple's on-device models first (unless the person chose their own AI only), then their service.
                var output: String?
                let preferences = KeyboardStore().preferences
                if preferences.aiEngine == .auto, action == .translate { output = try? await OnDeviceWriting.translate(text, to: language) }
                else if preferences.aiEngine == .auto, OnDeviceWriting.supportsRewrite(language: language.code) { output = try? await OnDeviceWriting.rewrite(text, action: action, language: language) }
                if output == nil { output = try await WritingService.perform(text: text, action: action, language: language) }
                if !Task.isCancelled { result = output ?? "" }
            } catch { if !Task.isCancelled { status = error.localizedDescription } }
        }
    }
}

private struct PrivacyView: View {
    var body: some View {
        List {
            Section("Your typing stays local") {
                Text("Basic typing, spelling suggestions, swipe decoding and emoji run on your iPhone. The app has no analytics, advertising SDK or keystroke logger.")
                Text("Optional learning stores individual word counts only. Clipboard history is off until you turn it on; it keeps text copied while the keyboard is open, skips password-manager copies and stays on this iPhone. Pinned text is kept until you delete it. All of it can be deleted in settings.")
            }
            Section("When data can leave your device") {
                Text("Translation and rewriting run on this iPhone when Apple's on-device models support the language. Otherwise, writing tools and GIF search send only the text or search words you choose to WianTribe's Cloudflare service. Online writing is processed by Groq; GIF previews load from GIPHY. Sign in with Apple connects the app and keyboard securely.")
                Text("Voice recording is available in this app, with microphone and speech permission. Apple's speech recognition may process audio on Apple's servers when on-device recognition is unavailable.")
            }
            Section("Full Access is optional") {
                Text("Use the keyboard without Full Access for normal typing. Clipboard history, GIFs, copying stickers, haptics, shared-container writes and your online service need Full Access. Allowing it does not start background text uploads.")
            }
            Section("iOS limits") {
                Text("Password fields and phone-number pads use Apple's keyboard. Apps may disable third-party keyboards. Media is copied to the clipboard; you paste it yourself in an app that accepts that format.")
                Text("The keyboard can't open a microphone or launch the voice editor. Open the app yourself to record, then copy the transcript. Apple's own dictation button may appear below the keyboard on supported devices.")
            }
        }.scrollContentBackground(.hidden).background(ocean).navigationTitle("Privacy & limits")
    }
}


private struct TesterFeedbackView: View {
    @State private var details = ""
    private var diagnostics: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "WianTribe Keyboard \(version) (\(build))\n\(UIDevice.current.model), \(UIDevice.current.systemName) \(UIDe…8112 tokens truncated…ltiplier: 0.105).isActive = true }
        returnKey.widthAnchor.constraint(equalTo: stack.widthAnchor, multiplier: 0.16).isActive = true
        keys.addArrangedSubview(stack)
    }

    var returnTitle: String {
        switch textDocumentProxy.returnKeyType ?? .default {
        case .go: return "Go"; case .search: return "Search"; case .send: return "Send"; case .done: return "Done"; case .next: return "Next"; default: return "↵"
        }
    }

    /// A punctuation key: tap for the main character, hold and slide for alternatives.
    func punctuationKey(_ title: String, alternates: [String]) -> KeyButton {
        let key = button(title) { [weak self] in self?.insert(title) }
        key.alternates = alternates
        key.accessibilityHint = "Hold for more punctuation"
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(accent(_:)))
        hold.minimumPressDuration = 0.38; key.addGestureRecognizer(hold)
        addPreview(to: key)
        return key
    }

    func deleteKey() -> KeyButton {
        let key = button("⌫", function: true) { [weak self] in self?.delete() }
        key.accessibilityLabel = "Delete"
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(deleteHeld(_:)))
        hold.minimumPressDuration = 0.35; key.addGestureRecognizer(hold)
        return key
    }

    func returnPressed() {
        if searchMode != nil { submitSearch() } else { insert("\n") }
    }

    func insert(_ text: String) {
        if searchMode != nil { searchInput(text); return }
        crashNotice = false
        collapseToolbar()
        correction = nil; glideChoices = []; lastSpace = 0; freshClip = nil
        textDocumentProxy.insertText(text)
        if shift && !capsLock { shift = false; applyCase() }
        if text.hasSuffix("\n") { updateShift() }
        refreshSuggestions()
    }

    func space() {
        if searchMode != nil { searchInput(" "); return }
        let context = before, word = currentWord
        let now = Date.timeIntervalSinceReferenceDate
        if preferences.doubleSpacePeriod && plainTextField && context.hasSuffix(" ") && now - lastSpace < 0.65,
           let previous = context.dropLast().last, previous.isLetter || previous.isNumber {
            textDocumentProxy.deleteBackward(); textDocumentProxy.insertText(". ")
            correction = nil; lastSpace = 0; updateShift(); refreshSuggestions(); return
        }
        if !word.isEmpty, plainTextField, let expansion = shortcuts[word] {
            replaceCurrentWord(with: expansion)
            textDocumentProxy.insertText(" "); correction = nil
        } else if preferences.autocorrect && textDocumentProxy.autocorrectionType != .no && plainTextField,
                  let replacement = engine.autocorrection(for: word, protectedWords: protectedWords.union(store.learned.keys), supplemental: supplemental) {
            let record = CorrectionRecord(original: word, replacement: replacement, contextBefore: context)
            replaceCurrentWord(with: replacement)
            textDocumentProxy.insertText(" "); correction = record
        } else {
            correction = nil
            textDocumentProxy.insertText(" ")
            if plainTextField { store.learn(pack.lowercased(word)) }
        }
        if plainTextField && !word.isEmpty { store.learnPair(previous: TextContext.previousWord(in: context), word: pack.lowercased(word)) }
        glideChoices = []; lastSpace = now; updateShift(); refreshSuggestions()
    }

    func replaceCurrentWord(with text: String) {
        for _ in currentWord { textDocumentProxy.deleteBackward() }
        textDocumentProxy.insertText(text)
    }

    func delete() {
        if searchMode != nil { searchDelete(); return }
        glideChoices = []; lastSpace = 0
        if let correction, correction.canUndo(context: before) {
            for _ in correction.replacement + " " { textDocumentProxy.deleteBackward() }
            textDocumentProxy.insertText(correction.original)
            self.correction = nil
        } else { textDocumentProxy.deleteBackward(); correction = nil }
        updateShift(); refreshSuggestions()
    }

    @objc func deleteHeld(_ gesture: UILongPressGestureRecognizer) {
        guard let key = gesture.view as? KeyButton else { return }
        if gesture.state == .began {
            key.longPressConsumed = true; delete()
            repeatDelete = Timer.scheduledTimer(withTimeInterval: 0.075, repeats: true) { [weak self] _ in self?.delete() }
        } else if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed {
            repeatDelete?.invalidate(); repeatDelete = nil
            DispatchQueue.main.async { key.longPressConsumed = false }
        }
    }

    func toggleShift() {
        let now = Date.timeIntervalSinceReferenceDate
        if now - lastShift < 0.3 { capsLock = true; shift = true }
        else if capsLock { capsLock = false; shift = false }
        else { shift.toggle() }
        lastShift = now; applyCase()
    }

    /// Updates letter labels for shift and caps lock in place. Rebuilding every key here would
    /// drop a tap that is already landing on the next key.
    func applyCase() {
        guard panel == nil, mode == "letters", !letterButtons.isEmpty else { rebuildContent(); return }
        let upper = shift || capsLock
        for key in letterButtons {
            guard let letter = key.letter else { continue }
            let title = upper ? pack.uppercased(String(letter)) : String(letter)
            UIView.performWithoutAnimation { key.setTitle(title, for: .normal); key.layoutIfNeeded() }
            key.accessibilityLabel = title
        }
        if let shiftKey {
            UIView.performWithoutAnimation { shiftKey.setTitle(capsLock ? "⇪" : "⇧", for: .normal); shiftKey.layoutIfNeeded() }
            shiftKey.accessibilityLabel = capsLock ? "Caps lock on" : "Shift"
            shiftKey.accessibilityValue = shift ? "On" : nil
        }
    }

    func updateShift(rebuild: Bool = true) {
        guard pack.isCased else { if shift || capsLock { shift = false; capsLock = false }; return }
        guard !capsLock, preferences.autoCapitalization else { return }
        let capitalization = textDocumentProxy.autocapitalizationType ?? .sentences
        let wanted: Bool
        switch capitalization {
        case .none: wanted = false
        case .allCharacters: wanted = true
        case .words: wanted = before.isEmpty || before.last?.isWhitespace == true
        default: wanted = plainTextField && TextContext.shouldCapitalize(after: before)
        }
        if wanted != shift { shift = wanted; if rebuild && panel == nil && mode == "letters" { applyCase() } }
    }

    @objc func moveCursor(_ gesture: UIPanGestureRecognizer) {
        guard searchMode == nil else { return }
        correction = nil; glideChoices = []
        let offset = Int(gesture.translation(in: view).x / 12)
        if offset != 0 { textDocumentProxy.adjustTextPosition(byCharacterOffset: offset); gesture.setTranslation(.zero, in: view) }
        if gesture.state == .ended { updateShift(); refreshSuggestions() }
    }

    func refreshSuggestions() {
        if searchMode != nil { showSearchResults(); return }
        guard panel == nil else { return }
        if crashNotice && currentWord.isEmpty {
            setStatus("iOS closed WianTribe last time, so it started in light mode (count in ⚙︎)"); return
        }
        suggestionWork?.cancel(); generation += 1
        if let correction, correction.canUndo(context: before) {
            showSuggestions([(correction.original + " ↶", { [weak self] in self?.delete() })]); return
        }
        if !glideChoices.isEmpty && before.hasSuffix(glideSuffix) {
            showSuggestions(glideChoices.map { word in (word, { [weak self] in self?.chooseGlide(word) }) }); return
        }
        let clipChoice = recentClipChoice()
        guard preferences.predictions && plainTextField else {
            if let clipChoice { showSuggestions([clipChoice]) } else { clear(suggestionBar); setStatus(preferences.language.title) }
            return
        }
        let word = currentWord, context = before, previous = TextContext.previousWord(in: before)
        let engine = self.engine, learned = store.learned, pairs = store.learnedPairs, supplemental = self.supplemental
        let checkerLanguage = Self.checkerLanguage(for: pack)
        let thisGeneration = generation
        // Emoji for the word being typed, or for the word just finished when the cursor follows a space.
        let emojiWord = word.isEmpty ? (context.last?.isWhitespace == true && context.last != "\n" ? previous : "") : word
        let emojiLanguages = preferences.emojiPredictions ? preferences.activeLanguages.map(\.code) : []
        let recentEmoji = preferences.emojiPredictions ? store.recentEmoji : []
        let tone = preferences.skinTone
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            var native: [String] = []
            // Apple's spelling dictionary adds words for any language installed on the phone.
            if let checkerLanguage, word.count > 1 && word.count < 32 {
                let range = NSRange(location: 0, length: (word as NSString).length)
                native = self.checker.completions(forPartialWordRange: range, in: word, language: checkerLanguage) ?? []
                if native.isEmpty { native = self.checker.guesses(forWordRange: range, in: word, language: checkerLanguage) ?? [] }
            }
            let results = engine.suggestions(for: word, previous: previous, learned: learned, learnedPairs: pairs, supplemental: supplemental + Array(native.prefix(12)))
            let emoji = emojiLanguages.isEmpty || emojiWord.isEmpty ? [] :
                EmojiCatalog.shared.predictions(for: emojiWord, languages: emojiLanguages, recent: recentEmoji, limit: word.isEmpty ? 3 : 1).map { $0.toned(tone) }
            DispatchQueue.main.async {
                guard self.generation == thisGeneration, self.before == context, self.panel == nil else { return }
                self.currentSuggestions = results
                var choices: [(String, () -> Void)] = results.map { result in (result.text, { [weak self] in self?.chooseSuggestion(result.text, expectedContext: context) }) }
                if !word.isEmpty { choices.insert((word, { [weak self] in self?.chooseSuggestion(word, expectedContext: context) }), at: 0) }
                if word.isEmpty, let clipChoice { choices.insert(clipChoice, at: 0) }
                // Emoji take the last slot while typing a word, or fill the bar right after one.
                let emojiChoices: [(String, () -> Void)] = emoji.map { symbol in (symbol, { [weak self] in self?.chooseEmojiSuggestion(symbol, expectedContext: context) }) }
                if !emojiChoices.isEmpty {
                    choices = word.isEmpty ? Array((choices.prefix(clipChoice == nil ? 0 : 1) + emojiChoices).prefix(3)) : Array(choices.prefix(2)) + emojiChoices
                }
                self.showSuggestions(Array(choices.prefix(3)))
            }
        }
        suggestionWork = work
        suggestionQueue.asyncAfter(deadline: .now() + 0.04, execute: work)
    }

    static func checkerLanguage(for pack: LanguagePack) -> String? {
        let available = UITextChecker.availableLanguages
        if available.contains(pack.checker) { return pack.checker }
        let base = pack.checker.split(separator: "_").first.map(String.init) ?? pack.checker
        return available.first { $0 == base || $0.hasPrefix(base + "_") }
    }

    func showSuggestions(_ choices: [(String, () -> Void)]) {
        clear(suggestionBar)
        if choices.isEmpty { setStatus(preferences.language.title); return }
        if panel == nil && searchMode == nil { suggestionBar.addArrangedSubview(toolbarToggle()) }
        let row = UIStackView(); row.axis = .horizontal; row.distribution = .fillEqually; row.spacing = 3
        for (text, action) in choices {
            let key = button(text, action: action)
            key.backgroundColor = .clear; key.normalColor = .clear; key.layer.shadowOpacity = 0; key.layer.borderWidth = 0
            key.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
            key.setTitleColor(palette.accent, for: .normal)
            row.addArrangedSubview(key)
        }
        suggestionBar.addArrangedSubview(row)
    }

    func chooseSuggestion(_ word: String, expectedContext: String) {
        guard before == expectedContext else { refreshSuggestions(); return }
        replaceCurrentWord(with: word)
        textDocumentProxy.insertText(" ")
        correction = nil; glideChoices = []
        if plainTextField {
            store.learn(pack.lowercased(word))
            store.learnPair(previous: TextContext.previousWord(in: expectedContext), word: pack.lowercased(word))
        }
        updateShift(); refreshSuggestions()
    }

    /// Types a suggested emoji: after the word being typed ("love ❤️ "), or straight after the last word's space.
    func chooseEmojiSuggestion(_ emoji: String, expectedContext: String) {
        guard before == expectedContext else { refreshSuggestions(); return }
        crashNotice = false; correction = nil; glideChoices = []
        let needsSpace = !(before.last?.isWhitespace ?? true)
        textDocumentProxy.insertText((needsSpace ? " " : "") + emoji + " ")
        store.useEmoji(emoji)
        updateShift(); refreshSuggestions()
    }

    func setStatus(_ text: String) {
        clear(suggestionBar)
        if panel == nil && searchMode == nil { suggestionBar.addArrangedSubview(toolbarToggle()) }
        let label = UILabel(); label.text = text; label.textColor = palette.accent
        label.font = .systemFont(ofSize: 12, weight: .medium); label.textAlignment = .center
        label.numberOfLines = 2; label.adjustsFontSizeToFitWidth = true
        suggestionBar.addArrangedSubview(label)
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === swipeGesture else { return true }
        guard searchMode == nil, preferences.swipeTyping, mode == "letters", plainTextField, !UIAccessibility.isVoiceOverRunning else { return false }
        let point = gestureRecognizer.location(in: keys)
        return letterButtons.contains { $0.convert($0.bounds, to: keys).contains(point) }
    }

    @objc func glide(_ gesture: UIPanGestureRecognizer) {
        let location = gesture.location(in: content)
        if gesture.state == .began {
            removeAccentPopup(); correction = nil; glideChoices = []
            let translation = gesture.translation(in: content)
            glidePath = [GlidePoint(x: Double(location.x - translation.x), y: Double(location.y - translation.y))]
            glideContext = before; glideShift = shift || capsLock
        }
        if gesture.state == .began || gesture.state == .changed {
            glidePath.append(GlidePoint(x: Double(location.x), y: Double(location.y)))
            if glidePath.count > 500 { glidePath = decoder.resample(glidePath, count: 250) }
            let path = UIBezierPath()
            for (i, point) in glidePath.enumerated() {
                let cg = CGPoint(x: point.x, y: point.y)
                if i == 0 { path.move(to: cg) } else { path.addLine(to: cg) }
            }
            glideLayer.path = path.cgPath
        }
        if gesture.state == .ended {
            glideLayer.path = nil
            guard before == glideContext else { return }
            var centers: [Character: GlidePoint] = [:]
            for key in letterButtons {
                let frame = key.convert(key.bounds, to: content)
                if let letter = key.letter { centers[letter] = GlidePoint(x: Double(frame.midX), y: Double(frame.midY)) }
            }
            let width = Double(letterButtons.first?.bounds.width ?? 32)
            let starts = decoder.startLetters(path: glidePath, centers: centers, keyWidth: width)
            let choices = decoder.decode(path: glidePath, centers: centers, words: engine.glideWords(startingWith: starts), keyWidth: width)
            guard !choices.isEmpty else { setStatus("Swipe a little more slowly, or tap to type"); return }
            glideChoices = choices.map { capsLock ? pack.uppercased($0.word) : (glideShift ? pack.uppercased(String($0.word.prefix(1))) + $0.word.dropFirst() : $0.word) }
            let prefix = !before.isEmpty && before.last?.isWhitespace == false ? " " : ""
            glideInserted = glideChoices[0]
            collapseToolbar()
            textDocumentProxy.insertText(prefix + glideInserted + " ")
            glideSuffix = String(before.suffix(64))
            if glideSuffix.isEmpty { glideChoices = [] }
            if !capsLock { shift = false }
            applyCase(); refreshSuggestions()
        } else if gesture.state == .cancelled || gesture.state == .failed { glideLayer.path = nil }
    }

    func chooseGlide(_ word: String) {
        guard before.hasSuffix(glideSuffix) else { glideChoices = []; refreshSuggestions(); return }
        for _ in glideInserted + " " { textDocumentProxy.deleteBackward() }
        textDocumentProxy.insertText(word + " ")
        glideInserted = word; glideSuffix = String(before.suffix(64)); refreshSuggestions()
    }

    func accents(for key: KeyButton, letter: Character) -> [String] {
        var values = [String(letter)] + (pack.alternates[String(letter)] ?? [])
        if (shift || capsLock) { values = values.map { pack.uppercased($0) } }
        if let symbol = key.hintText { values.append(symbol) }
        return values
    }

    @objc func accent(_ gesture: UILongPressGestureRecognizer) {
        guard let key = gesture.view as? KeyButton, key.letter != nil || !key.alternates.isEmpty else { return }
        let letter: Character = key.letter ?? " "
        if gesture.state == .began {
            key.longPressConsumed = true; hideKeyPreview()
            accentValues = key.alternates.isEmpty ? accents(for: key, letter: letter) : key.alternates
            accentSelection = min(1, accentValues.count - 1)
            let popup = UIStackView(); popup.axis = .horizontal; popup.distribution = .fillEqually; popup.spacing = 2
            popup.backgroundColor = palette.function; popup.layer.cornerRadius = 8; popup.clipsToBounds = true
            let width = min(content.bounds.width - 8, CGFloat(accentValues.count) * 32)
            let frame = key.convert(key.bounds, to: view)
            popup.frame = CGRect(x: min(max(4, frame.midX - width / 2), view.bounds.width - width - 4), y: max(0, frame.minY - 46), width: width, height: 40)
            for value in accentValues {
                let label = UILabel(); label.text = value; label.textAlignment = .center; label.textColor = palette.text
                label.font = .systemFont(ofSize: 20); popup.addArrangedSubview(label)
            }
            view.addSubview(popup); accentPopup = popup; highlightAccent()
        } else if gesture.state == .changed, let popup = accentPopup {
            let x = gesture.location(in: popup).x
            accentSelection = min(accentValues.count - 1, max(0, Int(x / (popup.bounds.width / CGFloat(accentValues.count)))))
            highlightAccent()
        } else if gesture.state == .ended {
            let chosen = accentValues.indices.contains(accentSelection) ? accentValues[accentSelection] : String(letter)
            removeAccentPopup(); insert(chosen)
            DispatchQueue.main.async { key.longPressConsumed = false }
        } else if gesture.state == .cancelled || gesture.state == .failed { removeAccentPopup(); key.longPressConsumed = false }
    }

    func highlightAccent() {
        for (i, label) in (accentPopup?.arrangedSubviews ?? []).enumerated() {
            label.backgroundColor = i == accentSelection ? palette.accent.withAlphaComponent(0.3) : .clear
        }
    }
    func removeAccentPopup() { accentPopup?.removeFromSuperview(); accentPopup = nil }

    func note(_ text: String, in stack: UIStackView) {
        let label = UILabel(); label.text = text; label.textColor = palette.text.withAlphaComponent(0.8)
        label.font = .systemFont(ofSize: 12); label.numberOfLines = 0; stack.addArrangedSubview(label)
    }
    func panelButton(_ title: String, in stack: UIStackView, action: @escaping () -> Void) {
        let key = button(title, action: action); key.heightAnchor.constraint(equalToConstant: 36).isActive = true
        key.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium); stack.addArrangedSubview(key)
    }

    func buildLanguages(_ stack: UIStackView) {
        note("Tap a language to type in it. Use ＋ to add it to your languages; the language key switches between them. Up to 6.", in: stack)
        panelButton("\(preferences.multilingual ? "✓ " : "○ ")Multilingual typing (suggest from all my languages)", in: stack) { [weak self] in
            guard let self else { return }; self.preferences.multilingual.toggle(); self.savePreferences()
        }
        let enabled = preferences.activeLanguages
        let ordered = enabled.map(\.pack) + LanguageCatalog.all.filter { pack in !enabled.contains { $0.code == pack.code } }
            .sorted { $0.englishName < $1.englishName }
        for pack in ordered {
            let isOn = enabled.contains { $0.code == pack.code }
            let line = UIStackView(); line.axis = .horizontal; line.spacing = 5
            let current = pack.code == preferences.language.code
            let title = (current ? "● " : "") + pack.name + (pack.name == pack.englishName ? "" : " · \(pack.englishName)") + (pack.hasDictionary ? "" : " (layout only)")
            let choose = button(title) { [weak self] in
                guard let self else { return }
                let language = KeyboardLanguage(pack.code)
                if !self.preferences.languages.contains(language) { self.preferences.languages = Array((self.preferences.activeLanguages + [language]).suffix(6)) }
                self.preferences.language = language
                self.correction = nil; self.glideChoices = []
                self.savePreferences(); self.showPanel(nil)
            }
            choose.titleLabel?.font = .systemFont(ofSize: 14, weight: current ? .semibold : .regular)
            choose.contentHorizontalAlignment = .leading
            let toggle = button(isOn ? "✓" : "＋", function: true) { [weak self] in
                guard let self else { return }
                let language = KeyboardLanguage(pack.code)
                var list = self.preferences.activeLanguages
                if isOn {
                    guard language != self.preferences.language else { self.setStatus("This is the language you're typing in"); return }
                    list.removeAll { $0 == language }
                } else {
                    guard list.count < 6 else { self.setStatus("Remove a language first (up to 6)"); return }
                    list.append(language)
                }
                self.preferences.languages = list
                self.savePreferences(); self.rebuildContent()
            }
            toggle.accessibilityLabel = isOn ? "Remove \(pack.englishName)" : "Add \(pack.englishName)"
            toggle.widthAnchor.constraint(equalToConstant: 44).isActive = true
            line.addArrangedSubview(choose); line.addArrangedSubview(toggle)
            line.heightAnchor.constraint(equalToConstant: 36).isActive = true
            stack.addArrangedSubview(line)
        }
        note("Word lists: wordfreq by Robyn Speer, CC BY-SA 4.0. Yorùbá and Pidgin lists by WianTribe.", in: stack)
    }

    func buildSettings(_ stack: UIStackView) {
        if let undo = writingUndo {
            panelButton("Undo last AI replacement", in: stack) { [weak self] in
                guard let self else { return }
                guard self.textDocumentProxy.documentIdentifier == undo.documentID,
                      self.textDocumentProxy.selectedText?.isEmpty != false,
                      self.before.hasSuffix(undo.replacement) else { self.setStatus("Text or cursor changed. Undo is no longer safe"); return }
                for _ in undo.replacement { self.textDocumentProxy.deleteBackward() }
                self.textDocumentProxy.insertText(undo.original); self.writingUndo = nil; self.showPanel(nil)
            }
        }
        let closes = store.unexpectedCloses
        note("Health: " + (closes == 0 ? "no unexpected closes" : "iOS closed the keyboard unexpectedly \(closes) time\(closes == 1 ? "" : "s"). Please report this with your iPhone model.") + (safeMode ? " Light mode is on for this session." : ""), in: stack)
        if closes > 0 { panelButton("Reset health counter", in: stack) { [weak self] in self?.store.unexpectedCloses = 0; self?.rebuildContent() } }
        note("Changes here apply immediately. Basic typing works without Full Access.", in: stack)
        panelButton("Languages: \(preferences.activeLanguages.map(\.shortTitle).joined(separator: " · "))", in: stack) { [weak self] in self?.showPanel("languages") }
        for theme in KeyboardTheme.allCases {
            panelButton("\(preferences.theme == theme ? "✓ " : "")\(theme.title)", in: stack) { [weak self] in self?.preferences.theme = theme; self?.savePreferences() }
        }
        panelButton("AI: \(preferences.aiEngine.title)", in: stack) { [weak self] in
            guard let self else { return }
            self.preferences.aiEngine = self.preferences.aiEngine == .auto ? .service : .auto
            self.savePreferences()
        }
        panelButton("Accent colour: \(preferences.accent.title)", in: stack) { [weak self] in
            guard let self else { return }
            let all = KeyAccent.allCases
            self.preferences.accent = all[((all.firstIndex(of: self.preferences.accent) ?? 0) + 1) % all.count]
            self.savePreferences()
        }
        for (title, keyPath) in [("Key sounds", \KeyboardPreferences.keySounds), ("Key pop-up preview", \KeyboardPreferences.keyPreview), ("Key outlines", \KeyboardPreferences.keyBorders), ("Number row", \KeyboardPreferences.numberRow), ("Autocorrect", \KeyboardPreferences.autocorrect), ("Suggestions", \KeyboardPreferences.predictions), ("Emoji suggestions", \KeyboardPreferences.emojiPredictions), ("Swipe typing", \KeyboardPreferences.swipeTyping), ("Auto capitals", \KeyboardPreferences.autoCapitalization), ("Double-space period", \KeyboardPreferences.doubleSpacePeriod), ("Haptic feedback", \KeyboardPreferences.haptics), ("Private typing (pause capture and learning)", \KeyboardPreferences.privateMode), ("Clipboard history", \KeyboardPreferences.clipboardHistory), ("Learn my words locally", \KeyboardPreferences.learnWords)] {
            panelButton("\(preferences[keyPath: keyPath] ? "✓ " : "○ ")\(title)", in: stack) { [weak self] in
                guard let self else { return }; self.preferences[keyPath: keyPath].toggle(); self.savePreferences()
            }
        }
        panelButton("Keep recent clips: \(preferences.clipboardDays) day\(preferences.clipboardDays == 1 ? "" : "s")", in: stack) { [weak self] in
            guard let self else { return }
            let options = ClipboardHistory.dayOptions
            self.preferences.clipboardDays = options[((options.firstIndex(of: self.preferences.clipboardDays) ?? 0) + 1) % options.count]
            self.savePreferences()
        }
        for hand in HandMode.allCases {
            panelButton("\(preferences.handMode == hand ? "✓ " : "")\(hand.title)", in: stack) { [weak self] in self?.preferences.handMode = hand; self?.savePreferences() }
        }
        for height in KeyboardPreferences.heights {
            panelButton("\(preferences.height == height ? "✓ " : "")Height: \(Int(height))", in: stack) { [weak self] in self?.preferences.height = height; self?.savePreferences() }
        }
        panelButton("Clear learned words", in: stack) { [weak self] in self?.store.learned = [:]; self?.store.learnedPairs = [:]; self?.setStatus("Learned words cleared") }
        note(store.isShared ? "Settings and phrases are shared with the app." : "Sideloaded builds may keep app and keyboard settings separate. Use these controls for your keyboard.", in: stack)
    }

    // MARK: Clipboard history

    func startClipboardWatch() {
        clipboardTimer?.invalidate(); clipboardTimer = nil
        guard preferences.clipboardHistory, !preferences.privateMode, hasFullAccess else { return }
        checkClipboard()
        // iOS gives keyboards no clipboard notification, so check the change count while the keyboard is on screen.
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.checkClipboard() }
        RunLoop.main.add(timer, forMode: .common)
        clipboardTimer = timer
    }

    func checkClipboard() {
        guard preferences.clipboardHistory, !preferences.privateMode, hasFullAccess else { return }
        let pasteboard = UIPasteboard.general
        let count = pasteboard.changeCount
        guard count != store.lastChangeCount else { return }
        guard pasteboard.hasStrings else { store.lastChangeCount = count; return }
        guard let text = pasteboard.string else {
            // A keyboard can't show iOS's "Allow Paste?" prompt, so with the default "Ask" setting iOS
            // returns no text. Stop polling, explain the fix, and try again next time the keyboard opens.
            clipboardTimer?.invalidate(); clipboardTimer = nil
            if !clipboardBlocked {
                clipboardBlocked = true
                collapseToolbar()
                if panel == "clips" { rebuildContent() } else if panel == nil { refreshSuggestions() }
            }
            return
        }
        clipboardBlocked = false
        store.lastChangeCount = count
        store.clipboardWorked = true
        // Only text is kept. Password managers mark their copies, and those are skipped.
        guard ClipboardHistory.shouldCapture(text, types: pasteboard.types) else { return }
        if let data = text.data(using: .utf8), (try? JSONDecoder().decode(WritingConnection.self, from: data)) != nil { return }
        store.capture(text)
        freshClip = (text, Date())
        collapseToolbar() // Show the "just copied" chip, like Android's clipboard suggestion.
        if panel == "clips" { rebuildContent() } else if panel == nil { refreshSuggestions() }
    }

    /// A "just copied" chip for the suggestion bar, shown for two minutes or until typing starts.
    func recentClipChoice() -> (String, () -> Void)? {
        if clipboardBlocked && currentWord.isEmpty {
            return ("📋 Allow clipboard access", { [weak self] in self?.showPanel("clips") })
        }
        guard let clip = freshClip, Date().timeIntervalSince(clip.date) < 120, currentWord.isEmpty else { return nil }
        return ("📋 " + ClipboardHistory.preview(clip.text, length: 18), { [weak self] in
            self?.freshClip = nil; self?.insert(clip.text)
        })
    }

    func copyToClipboard(_ text: String) {
        guard hasFullAccess else { setStatus("Copying needs Allow Full Access in Settings"); return }
        UIPasteboard.general.string = text
        store.lastChangeCount = UIPasteboard.general.changeCount
        if preferences.clipboardHistory { store.capture(text) }
        if panel == "clips" { rebuildContent() }
        setStatus("Copied. Paste it anywhere")
    }

    func buildClipboard(_ stack: UIStackView) {
        panelButton(clipQuery.isEmpty ? "Search clipboard" : "Search: \(clipQuery)", in: stack) { [weak self] in self?.enterSearch(.clips) }
        if !clipQuery.isEmpty { panelButton("Clear search", in: stack) { [weak self] in self?.clipQuery = ""; self?.rebuildContent() } }
        if !hasFullAccess {
            note("To keep what you copy in other apps, turn on Allow Full Access: Settings → General → Keyboard → Keyboards → WianTribe Keyboard. You can still save selected text below.", in: stack)
        } else if !preferences.clipboardHistory {
            note("Clipboard history keeps the last \(ClipboardHistory.maxRecent) things you copy, so you can paste them anywhere. It stays on this iPhone, and copies from password managers are skipped.", in: stack)
            panelButton("Turn on clipboard history", in: stack) { [weak self] in
                guard let self else { return }
                self.preferences.clipboardHistory = true
                self.store.lastChangeCount = -1 // Include what is already on the clipboard.
                self.savePreferences(); self.showPanel("clips")
            }
        } else if clipboardBlocked || !store.clipboardWorked {
            note(clipboardBlocked
                 ? "⚠️ iOS is blocking the clipboard. Open Settings → Apps → WianTribe Keyboard → Paste from Other Apps and choose Allow. (If you don't see it, open the WianTribe app → Tools → Clipboard → Test clipboard access first.)"
                 : "Copy some text in any app, then come back. If nothing appears, open Settings → Apps → WianTribe Keyboard → Paste from Other Apps and choose Allow.", in: stack)
            panelButton("Check the clipboard again", in: stack) { [weak self] in
                guard let self else { return }
                self.clipboardBlocked = false
                self.store.lastChangeCount = -1
                self.startClipboardWatch()
                if !self.clipboardBlocked { self.rebuildContent() }
                self.setStatus(self.clipboardBlocked ? "Still blocked. Check Paste from Other Apps" : (self.store.clipboardWorked ? "Clipboard access works" : "Nothing new on the clipboard yet"))
            }
        }
        let actions = UIStackView(); actions.axis = .horizontal; actions.distribution = .fillEqually; actions.spacing = 5
        let copy = button("Copy selected") { [weak self] in
            guard let self else { return }
            guard let selected = self.textDocumentProxy.selectedText, !selected.isEmpty else { self.setStatus("Select text in your message first"); return }
            self.copyToClipboard(selected)
        }
        let save = button("Pin selected") { [weak self] in
            guard let self else { return }
            guard let selected = self.textDocumentProxy.selectedText, !selected.isEmpty else { self.setStatus("Select text in your message first"); return }
            self.store.addPhrase(selected); self.rebuildContent(); self.setStatus("Pinned on this device")
        }
        let clearRecent = button("Clear recent") { [weak self] in
            self?.store.clearRecentClips(); self?.freshClip = nil; self?.rebuildContent(); self?.setStatus("Recent clips cleared. Pinned items kept")
        }
        for key in [copy, save, clearRecent] { key.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium); actions.addArrangedSubview(key) }
        actions.heightAnchor.constraint(equalToConstant: 34).isActive = true
        stack.addArrangedSubview(actions)

        if store.hasGroup {
            note("Tip: save copies without opening the keyboard: double-tap the back of your iPhone (Back Tap), or Share → Save to WianTribe. Set it up in the WianTribe app → Tools → Clipboard.", in: stack)
        }
        let items = ClipboardHistory.ordered(store.phrases).filter { clipQuery.isEmpty || $0.text.localizedCaseInsensitiveContains(clipQuery) }
        if items.isEmpty {
            note(preferences.clipboardHistory && hasFullAccess ? "Copy something in any app, then come back to this keyboard. It will appear here." : "Pinned text will appear here. You can paste it while offline.", in: stack)
            return
        }
        var row: UIStackView?
        for (index, item) in items.enumerated() {
            if index % 2 == 0 {
                let next = UIStackView(); next.axis = .horizontal; next.distribution = .fillEqually; next.spacing = 6
                stack.addArrangedSubview(next); row = next
            }
            row?.addArrangedSubview(clipCard(item))
        }
        if items.count % 2 == 1 { row?.addArrangedSubview(UIView()) } // Keep the last card half width.
    }

    func clipCard(_ item: SavedPhrase) -> UIView {
        let card = UIStackView(); card.axis = .vertical
        card.backgroundColor = palette.key; card.layer.cornerRadius = 8; card.layer.cornerCurve = .continuous; card.clipsToBounds = true
        let body = button((item.pinned ? "📌 " : "") + String(item.text.prefix(160))) { [weak self] in
            self?.insert(item.text); self?.showPanel(nil)
        }
        body.titleLabel?.font = .systemFont(ofSize: 13)
        body.titleLabel?.adjustsFontSizeToFitWidth = false
        body.titleLabel?.numberOfLines = 3; body.titleLabel?.lineBreakMode = .byTruncatingTail
        body.titleLabel?.textAlignment = .natural
        body.contentHorizontalAlignment = .leading; body.contentVerticalAlignment = .top
        body.contentEdgeInsets = UIEdgeInsets(top: 6, left: 8, bottom: 4, right: 6)
        body.layer.cornerRadius = 0; body.layer.shadowOpacity = 0
        body.accessibilityLabel = (item.pinned ? "Pinned: " : "") + String(item.text.prefix(120))
        body.accessibilityHint = "Pastes this text"
        body.heightAnchor.constraint(equalToConstant: 62).isActive = true

        let controls = UIStackView(); controls.axis = .horizontal; controls.distribution = .fillEqually; controls.spacing = 1
        let pin = button(item.pinned ? "Unpin" : "Pin", function: true) { [weak self] in
            guard let self else { return }
            var items = self.store.phrases
            if let i = items.firstIndex(where: { $0.id == item.id }) { items[i].pinned.toggle(); self.store.phrases = items }
            self.rebuildContent()
        }
        let copy = button("Copy", function: true) { [weak self] in self?.copyToClipboard(item.text) }
        let delete = button("✕", function: true) { [weak self] in
            self?.store.phrases.removeAll { $0.id == item.id }; self?.rebuildContent()
        }
        delete.accessibilityLabel = "Delete"
        for key in [pin, copy, delete] {
            key.titleLabel?.font = .systemFont(ofSize: 12, weight: .medium)
            key.layer.cornerRadius = 0; key.layer.shadowOpacity = 0
            controls.addArrangedSubview(key)
        }
        controls.heightAnchor.constraint(equalToConstant: 26).isActive = true
        card.addArrangedSubview(body); card.addArrangedSubview(controls)
        return card
    }

    /// The text writing tools work on: the selection, or else the paragraph typed before the cursor.
    func writingSource() -> (text: String, isSelection: Bool)? {
        if let selected = textDocumentProxy.selectedText, !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return (selected, true) }
        let paragraph = before.split(separator: "\n", omittingEmptySubsequences: false).last.map(String.init) ?? ""
        let text = String(paragraph.suffix(1500))
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : (text, false)
    }

    func buildServiceRows(_ stack: UIStackView) {
        if ConnectionVault.load() == nil {
            note("Open WianTribe → Tools → AI account and sign in with Apple. Your keyboard connects automatically. Allow Full Access is required for online AI.", in: stack)
        } else {
            note("WianTribe AI is connected. Manage your account or sign out in WianTribe → Tools → AI account.", in: stack)
        }
        note("Voice typing: use Apple's dictation button below the keyboard, or the companion app's Voice editor.", in: stack)
    }
}
