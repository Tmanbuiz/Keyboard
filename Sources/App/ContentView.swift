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
                Text("Choose “WianTribe AI online” to use online rewriting and translation. Sign in in Tools → AI account. The keyboard has the same switch under ⚙︎.")
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
        return "WianTribe Keyboard \(version) (\(build))\n\(UIDevice.current.model), \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)\nShared storage: \(KeyboardStore().hasGroup ? "available" : "unavailable")"
    }
    var body: some View {
        Form {
            Section("Describe the problem") {
                TextEditor(text: $details).frame(minHeight: 160)
                    .accessibilityLabel("Steps to reproduce, expected behaviour and what happened")
                Text("Include the app you were typing in and the steps to reproduce. Avoid passwords or private messages.").font(.caption)
            }
            Section("Build information") { Text(diagnostics).font(.caption).textSelection(.enabled) }
            Section {
                ShareLink(item: diagnostics + "\n\n" + details) { Label("Share feedback", systemImage: "square.and.arrow.up") }
                Text("Review the report and choose where to send it. Typed text, clipboard entries and access tokens are not added automatically.").font(.caption)
            }
        }.navigationTitle("TestFlight feedback")
    }
}
