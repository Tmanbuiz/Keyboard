import Foundation

public enum KeyboardTheme: String, Codable, CaseIterable, Identifiable {
    case auto, ocean, midnight, light, rose, forest, sunset, slate
    public var id: String { rawValue }
    public var title: String { self == .auto ? "Auto (light/dark)" : rawValue.capitalized }
}

/// Accent colours people can pick on top of any theme.
public enum KeyAccent: String, Codable, CaseIterable, Identifiable {
    case theme, mint, blue, purple, pink, orange, gold
    public var id: String { rawValue }
    public var title: String { self == .theme ? "Theme colour" : rawValue.capitalized }
    /// RGB components, or nil to keep the theme's own accent.
    public var rgb: (Double, Double, Double)? {
        switch self {
        case .theme: return nil
        case .mint: return (0.38, 0.88, 0.75)
        case .blue: return (0.29, 0.56, 1.0)
        case .purple: return (0.66, 0.50, 1.0)
        case .pink: return (1.0, 0.45, 0.66)
        case .orange: return (1.0, 0.58, 0.20)
        case .gold: return (0.95, 0.77, 0.25)
        }
    }
}

public enum HandMode: String, Codable, CaseIterable, Identifiable {
    case full, left, right
    public var id: String { rawValue }
    public var title: String { self == .full ? "Both hands" : "\(rawValue.capitalized) hand" }
}

public struct KeyboardPreferences: Codable, Equatable {
    /// The language whose layout is shown.
    public var language: KeyboardLanguage = LanguageCatalog.deviceLanguages().first ?? .english
    /// Languages the person switches between; with multilingual typing on, suggestions draw on all of them.
    public var languages: [KeyboardLanguage] = KeyboardPreferences.defaultLanguages()
    public var multilingual = true
    public var theme: KeyboardTheme = .auto
    public var accent: KeyAccent = .theme
    public var keySounds = true
    public var keyPreview = true
    public var keyBorders = false
    /// Default emoji skin tone: 0 is the standard yellow, 1–5 are light to dark.
    public var skinTone = 0
    public var aiEngine: AIEngine = .auto
    public var handMode: HandMode = .full
    public var numberRow = true
    public var autocorrect = true
    public var predictions = true
    /// Offer emoji in the suggestion bar for words like "love" or "pizza".
    public var emojiPredictions = true
    public var swipeTyping = true
    public var autoCapitalization = true
    public var doubleSpacePeriod = true
    public var haptics = false
    // Word learning is opt-in; never retain sentences or a keystroke history.
    public var learnWords = false
    public var height: Double = 300
    public static let heights: [Double] = [240, 270, 300, 330, 360]
    // Clipboard history is opt-in and stays on this device.
    public var privateMode = false
    public var clipboardHistory = false
    public var clipboardDays = 7
    public init() {}

    public static func defaultLanguages() -> [KeyboardLanguage] {
        let device = LanguageCatalog.deviceLanguages()
        return Array((device.isEmpty ? [.english] : device).prefix(3))
    }

    /// Enabled languages, always including the current one, without duplicates.
    public var activeLanguages: [KeyboardLanguage] {
        var result = [language]
        for item in languages where !result.contains(item) { result.append(item) }
        return result
    }

    // Missing keys fall back to defaults, so adding a setting never resets existing ones.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = KeyboardPreferences()
        language = (try? c.decodeIfPresent(KeyboardLanguage.self, forKey: .language)) ?? d.language
        languages = (try? c.decodeIfPresent([KeyboardLanguage].self, forKey: .languages)) ?? [language]
        multilingual = (try? c.decodeIfPresent(Bool.self, forKey: .multilingual)) ?? d.multilingual
        theme = (try? c.decodeIfPresent(KeyboardTheme.self, forKey: .theme)) ?? d.theme
        accent = (try? c.decodeIfPresent(KeyAccent.self, forKey: .accent)) ?? d.accent
        keySounds = (try? c.decodeIfPresent(Bool.self, forKey: .keySounds)) ?? d.keySounds
        keyPreview = (try? c.decodeIfPresent(Bool.self, forKey: .keyPreview)) ?? d.keyPreview
        keyBorders = (try? c.decodeIfPresent(Bool.self, forKey: .keyBorders)) ?? d.keyBorders
        skinTone = (try? c.decodeIfPresent(Int.self, forKey: .skinTone)) ?? d.skinTone
        aiEngine = (try? c.decodeIfPresent(AIEngine.self, forKey: .aiEngine)) ?? d.aiEngine
        handMode = (try? c.decodeIfPresent(HandMode.self, forKey: .handMode)) ?? d.handMode
        numberRow = (try? c.decodeIfPresent(Bool.self, forKey: .numberRow)) ?? d.numberRow
        autocorrect = (try? c.decodeIfPresent(Bool.self, forKey: .autocorrect)) ?? d.autocorrect
        predictions = (try? c.decodeIfPresent(Bool.self, forKey: .predictions)) ?? d.predictions
        emojiPredictions = (try? c.decodeIfPresent(Bool.self, forKey: .emojiPredictions)) ?? d.emojiPredictions
        swipeTyping = (try? c.decodeIfPresent(Bool.self, forKey: .swipeTyping)) ?? d.swipeTyping
        autoCapitalization = (try? c.decodeIfPresent(Bool.self, forKey: .autoCapitalization)) ?? d.autoCapitalization
        doubleSpacePeriod = (try? c.decodeIfPresent(Bool.self, forKey: .doubleSpacePeriod)) ?? d.doubleSpacePeriod
        haptics = (try? c.decodeIfPresent(Bool.self, forKey: .haptics)) ?? d.haptics
        learnWords = (try? c.decodeIfPresent(Bool.self, forKey: .learnWords)) ?? d.learnWords
        height = (try? c.decodeIfPresent(Double.self, forKey: .height)) ?? d.height
        clipboardHistory = (try? c.decodeIfPresent(Bool.self, forKey: .clipboardHistory)) ?? d.clipboardHistory
        privateMode = (try? c.decodeIfPresent(Bool.self, forKey: .privateMode)) ?? d.privateMode
        clipboardDays = (try? c.decodeIfPresent(Int.self, forKey: .clipboardDays)) ?? d.clipboardDays
    }
}

/// A clipboard item. Pinned items are saved phrases: they never expire.
public struct SavedPhrase: Codable, Identifiable, Equatable {
    public var id: UUID
    public var text: String
    public var pinned: Bool
    public var createdAt: Date
    public var folder: String? = nil
    public init(text: String, pinned: Bool = false, createdAt: Date = Date()) {
        id = UUID(); self.text = String(text.prefix(ClipboardHistory.maxLength)); self.pinned = pinned; self.createdAt = createdAt
    }
}

/// Writing Assist actions: rewrites change the style, formats change the shape of the text.
/// The instructions are shared by Apple's on-device model and Backend/worker.mjs.
/// Which AI handles writing tools and translation.
public enum AIEngine: String, Codable, CaseIterable, Identifiable {
    case auto, service
    public var id: String { rawValue }
    public var title: String { self == .auto ? "Apple first, then WianTribe AI" : "WianTribe AI online" }
}

public enum WritingAction: String, Codable, CaseIterable, Identifiable {
    case grammar, professional, casual, polite, social, emojify, shorter, longer, summary, bullets, table, email, translate
    public var id: String { rawValue }
    public static let rewrites: [WritingAction] = [.grammar, .professional, .casual, .polite, .social, .emojify, .shorter, .longer]
    public static let formats: [WritingAction] = [.summary, .bullets, .table, .email]

    public var title: String {
        switch self {
        case .grammar: return "Fix grammar & spelling"
        case .professional: return "Professional"
        case .casual: return "Casual"
        case .polite: return "Polite"
        case .social: return "Social post"
        case .emojify: return "Add emoji"
        case .shorter: return "Shorter"
        case .longer: return "Longer"
        case .summary: return "Summarise"
        case .bullets: return "Bullet points"
        case .table: return "Table"
        case .email: return "Email"
        case .translate: return "Translate"
        }
    }

    public var instruction: String {
        switch self {
        case .grammar: return "Correct grammar, spelling and punctuation. Keep the meaning, tone and language."
        case .professional: return "Rewrite in a clear, professional tone. Keep the meaning and language."
        case .casual: return "Rewrite in a friendly, casual tone. Keep the meaning and language."
        case .polite: return "Rewrite so it sounds polite, warm and respectful. Keep the meaning and language."
        case .social: return "Rewrite as an engaging social media post, ending with two to four relevant hashtags. Keep the language."
        case .emojify: return "Add a few fitting emoji to the text. Keep every word as it is."
        case .shorter: return "Make the text shorter and clearer, keeping the key points and the language."
        case .longer: return "Expand the text with a little more detail and smoother wording. Keep the meaning, tone and language. Do not invent facts."
        case .summary: return "Summarise the text in two or three sentences in the same language."
        case .bullets: return "Turn the text into a short list of key points, one per line, each starting with \"• \". Use the same language."
        case .table: return "Organise the information as a plain-text table: a header row, then one row per item, with columns separated by \" | \". Use the same language. Do not invent data; leave a cell empty if unknown."
        case .email: return "Format the text as a clear email: a greeting, short paragraphs and a closing line followed by [Your name]. Use the same language."
        case .translate: return "Translate the text into the requested language, preserving the meaning."
        }
    }
}

public enum TextContext {
    public static func isWordCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy {
            CharacterSet.letters.contains($0) || CharacterSet.nonBaseCharacters.contains($0)
                || $0 == "'" || $0 == "’"
        }
    }

    public static func currentWord(in text: String) -> String {
        String(text.reversed().prefix(while: isWordCharacter).reversed())
    }

    public static func previousWord(in text: String) -> String {
        let current = currentWord(in: text)
        let prefix = String(text.dropLast(current.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        return currentWord(in: prefix).lowercased()
    }

    public static func shouldCapitalize(after text: String) -> Bool {
        if text.isEmpty || text.hasSuffix("\n") { return true }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return [".", "!", "?"].contains(String(trimmed.suffix(1))) && trimmed.count < text.count
    }

    public static func matchingCase(_ candidate: String, to original: String, language: LanguagePack? = nil) -> String {
        let upper: (String) -> String = { language?.uppercased($0) ?? $0.uppercased() }
        if original.count > 1 && original.contains(where: \.isUppercase) && original == upper(original) { return upper(candidate) }
        if original.first?.isUppercase == true { return upper(String(candidate.prefix(1))) + candidate.dropFirst() }
        return candidate
    }

    public static func canLearn(_ word: String) -> Bool {
        let letters = word.filter { $0.isLetter }
        return (2...24).contains(word.count) && letters.count == word.count
            && word == word.lowercased() && !word.contains("@")
    }
}

// Undo is allowed only if the cursor still follows this exact correction.
public struct CorrectionRecord: Equatable {
    public let original: String
    public let replacement: String
    public let contextSuffix: String
    public init(original: String, replacement: String, contextBefore: String) {
        self.original = original; self.replacement = replacement
        contextSuffix = String((String(contextBefore.dropLast(original.count)) + replacement + " ").suffix(64))
    }
    public func canUndo(contex…23697 tokens truncated…     // iOS gives keyboards no clipboard notification, so check the change count while the keyboard is on screen.
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
