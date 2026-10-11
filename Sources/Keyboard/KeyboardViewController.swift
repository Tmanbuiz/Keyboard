import UIKit
import UniformTypeIdentifiers

final class KeyboardViewController: UIInputViewController, UIGestureRecognizerDelegate {
    private var store = KeyboardStore(canWriteGroup: false)
    private var preferences = KeyboardPreferences()
    private var palette = KeyboardPalette.make(.ocean)
    private let engine = SuggestionEngine.bundled()
    private let checker = UITextChecker()
    private let decoder = GlideDecoder()
    private let root = UIStackView()
    private let toolbar = UIStackView()
    private let suggestionBar = UIStackView()
    private let content = UIView()
    private var keys = UIStackView()
    private var heightConstraint: NSLayoutConstraint?
    private var panel: String?
    private var mode = "letters"
    private var shift = false
    private var capsLock = false
    private var lastShift: TimeInterval = 0
    private var lastSpace: TimeInterval = 0
    private var correction: CorrectionRecord?
    private var supplemental: [String] = []
    private var protectedWords = Set<String>()
    private var shortcuts: [String: String] = [:]
    private var suggestionWork: DispatchWorkItem?
    private let suggestionQueue = DispatchQueue(label: "com.wiantribe.keyboard.suggestions", qos: .userInitiated)
    private var generation = 0
    private var currentSuggestions: [WordSuggestion] = []
    private var letterButtons: [KeyButton] = []
    private var swipeGesture: UIPanGestureRecognizer?
    private var glidePath: [GlidePoint] = []
    private var glideLayer = CAShapeLayer()
    private var glideContext = ""
    private var glideChoices: [String] = []
    private var glideInserted = ""
    private var glideShift = false
    private var glideSuffix = ""
    private var repeatDelete: Timer?
    private var accentPopup: UIStackView?
    private var accentValues: [String] = []
    private var accentSelection = 0
    private var onlineTask: Task<Void, Never>?

    override func viewDidLoad() {
        super.viewDidLoad()
        hasDictationKey = false // Keep Apple's system dictation button where iOS provides one.
        root.axis = .vertical; root.spacing = 5
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            root.topAnchor.constraint(equalTo: view.topAnchor, constant: 4),
            root.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -5)
        ])
        toolbar.axis = .horizontal; toolbar.distribution = .fillEqually; toolbar.spacing = 3
        suggestionBar.axis = .horizontal; suggestionBar.distribution = .fillEqually; suggestionBar.spacing = 3
        root.addArrangedSubview(toolbar); root.addArrangedSubview(suggestionBar); root.addArrangedSubview(content)
        toolbar.heightAnchor.constraint(equalToConstant: 30).isActive = true
        suggestionBar.heightAnchor.constraint(equalToConstant: 32).isActive = true
        reloadPreferences()
        requestSupplementaryLexicon { [weak self] lexicon in
            DispatchQueue.main.async {
                guard let self else { return }
                self.supplemental = lexicon.entries.map(\.documentText)
                self.protectedWords = Set(lexicon.entries.map { $0.documentText.lowercased() })
                for entry in lexicon.entries where entry.userInput != entry.documentText {
                    self.shortcuts[entry.userInput] = entry.documentText
                }
                self.refreshSuggestions()
            }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadPreferences()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        repeatDelete?.invalidate(); repeatDelete = nil
        suggestionWork?.cancel(); onlineTask?.cancel()
        removeAccentPopup()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        if let correction, !correction.canUndo(context: before) { self.correction = nil }
        if !before.hasSuffix(glideSuffix) { glideChoices = [] }
        updateShift()
        refreshSuggestions()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        glideLayer.frame = content.bounds
        let wantedHeight = traitCollection.verticalSizeClass == .compact ? min(preferences.height, 205) : preferences.height
        if heightConstraint?.constant != wantedHeight { heightConstraint?.constant = wantedHeight }
    }

    private var before: String { textDocumentProxy.documentContextBeforeInput ?? "" }
    private var currentWord: String { TextContext.currentWord(in: before) }
    private var plainTextField: Bool {
        let type = textDocumentProxy.keyboardType ?? .default
        return ![.emailAddress, .URL, .numberPad, .decimalPad, .phonePad, .namePhonePad, .asciiCapableNumberPad].contains(type)
    }

    private func reloadPreferences() {
        store = KeyboardStore(canWriteGroup: hasFullAccess)
        preferences = store.preferences
        palette = .make(preferences.theme)
        view.backgroundColor = palette.background
        primaryLanguage = preferences.language == .yoruba ? "yo" : "en"
        if heightConstraint == nil {
            heightConstraint = view.heightAnchor.constraint(equalToConstant: preferences.height)
            heightConstraint?.priority = UILayoutPriority(999)
            heightConstraint?.isActive = true
        } else { heightConstraint?.constant = preferences.height }
        updateShift(rebuild: false)
        rebuildToolbar(); rebuildContent(); refreshSuggestions()
    }

    private func savePreferences() {
        store.preferences = preferences
        reloadPreferences()
    }

    private func clear(_ stack: UIStackView) {
        stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }
    }

    private func button(_ title: String, function: Bool = false, action: @escaping () -> Void) -> KeyButton {
        let key = KeyButton(title: title, palette: palette, function: function)
        key.onTap = { [weak self] in self?.feedback(); action() }
        return key
    }

    private func feedback() {
        if preferences.haptics && hasFullAccess { UISelectionFeedbackGenerator().selectionChanged() }
    }

    private func rebuildToolbar() {
        clear(toolbar)
        if panel != nil { toolbar.addArrangedSubview(button("ABC") { [weak self] in self?.showPanel(nil) }) }
        else { toolbar.addArrangedSubview(button(preferences.language.shortTitle) { [weak self] in self?.cycleLanguage() }) }
        for (title, identifier, label) in [("☺︎", "emoji", "Emoji and stickers"), ("▣", "clips", "Saved phrases"), ("✦", "writing", "Writing tools"), ("⚙︎", "settings", "Keyboard settings")] {
            let key = button(title) { [weak self] in self?.showPanel(identifier) }
            key.accessibilityLabel = label
            toolbar.addArrangedSubview(key)
        }
        if panel != nil {
            let globe = KeyButton(title: "🌐", palette: palette, function: true)
            globe.accessibilityLabel = "Next keyboard"
            globe.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
            toolbar.addArrangedSubview(globe)
        }
        let hide = button("⌄") { [weak self] in self?.dismissKeyboard() }
        hide.accessibilityLabel = "Hide keyboard"; toolbar.addArrangedSubview(hide)
    }

    private func cycleLanguage() {
        let all = KeyboardLanguage.allCases
        preferences.language = all[((all.firstIndex(of: preferences.language) ?? 0) + 1) % all.count]
        correction = nil; glideChoices = []; savePreferences()
    }

    private func showPanel(_ identifier: String?) {
        panel = identifier
        onlineTask?.cancel()
        rebuildToolbar(); rebuildContent()
        if identifier == nil { refreshSuggestions() } else { setStatus(panelTitle) }
    }

    private var panelTitle: String {
        switch panel { case "emoji": return "Emoji & media"; case "clips": return "Saved phrases"; case "writing": return "Writing tools"; default: return "Make it yours" }
    }

    private func rebuildContent() {
        repeatDelete?.invalidate(); repeatDelete = nil
        removeAccentPopup()
        content.subviews.forEach { $0.removeFromSuperview() }
        glideLayer.removeFromSuperlayer()
        letterButtons = []
        if let panel {
            let scroll = UIScrollView(); scroll.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(scroll)
            NSLayoutConstraint.activate([scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor), scroll.topAnchor.constraint(equalTo: content.topAnchor), scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor)])
            let stack = UIStackView(); stack.axis = .vertical; stack.spacing = 8; stack.translatesAutoresizingMaskIntoConstraints = false
            scroll.addSubview(stack)
            NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 5), stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -5), stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 3), stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -6), stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -10)])
            switch panel { case "emoji": buildEmoji(stack); case "clips": buildPhrases(stack); case "writing": buildWriting(stack); default: buildSettings(stack) }
            return
        }
        keys = UIStackView(); keys.axis = .vertical; keys.distribution = .fillEqually; keys.spacing = 6
        keys.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(keys)
        let width = keys.widthAnchor.constraint(equalTo: content.widthAnchor, multiplier: preferences.handMode == .full ? 1 : 0.86)
        let anchor: NSLayoutConstraint
        switch preferences.handMode {
        case .full: anchor = keys.centerXAnchor.constraint(equalTo: content.centerXAnchor)
        case .left: anchor = keys.leadingAnchor.constraint(equalTo: content.leadingAnchor)
        case .right: anchor = keys.trailingAnchor.constraint(equalTo: content.trailingAnchor)
        }
        NSLayoutConstraint.activate([width, anchor, keys.topAnchor.constraint(equalTo: content.topAnchor), keys.bottomAnchor.constraint(equalTo: content.bottomAnchor)])
        if mode == "letters" { buildLetters() } else { buildSymbols() }
        buildBottomRow()
        glideLayer.strokeColor = palette.accent.cgColor; glideLayer.lineWidth = 4
        glideLayer.fillColor = UIColor.clear.cgColor; glideLayer.lineCap = .round; glideLayer.lineJoin = .round
        content.layer.addSublayer(glideLayer)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(glide(_:)))
        pan.delegate = self; pan.cancelsTouchesInView = true
        keys.addGestureRecognizer(pan); swipeGesture = pan
    }

    private func row(_ buttons: [KeyButton], inset: CGFloat = 0) {
        let container = UIView()
        let stack = UIStackView(arrangedSubviews: buttons); stack.axis = .horizontal; stack.distribution = .fillEqually; stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false; container.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: inset), stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -inset), stack.topAnchor.constraint(equalTo: container.topAnchor), stack.bottomAnchor.constraint(equalTo: container.bottomAnchor)])
        keys.addArrangedSubview(container)
    }

    private let hints: [Character: String] = ["q":"1", "w":"2", "e":"3", "r":"4", "t":"5", "y":"6", "u":"7", "i":"8", "o":"9", "p":"0", "a":"@", "s":"#", "d":"$", "f":"%", "g":"&", "h":"*", "j":"-", "k":"+", "l":"=", "z":"!", "x":"?", "c":"'", "v":"\"", "b":":", "n":";", "m":"/"]

    private func buildLetters() {
        if preferences.numberRow { row(Array("1234567890").map { character in button(String(character)) { [weak self] in self?.insert(String(character)) } }) }
        for (index, letters) in ["qwertyuiop", "asdfghjkl", "zxcvbnm"].enumerated() {
            var buttons: [KeyButton] = letters.map { letter in
                let key = KeyButton(title: (shift || capsLock) ? String(letter).uppercased() : String(letter), hint: hints[letter], palette: palette)
                key.letter = letter
                key.onTap = { [weak self] in
                    guard let self else { return }
                    self.feedback(); self.insert((self.shift || self.capsLock) ? String(letter).uppercased() : String(letter))
                }
                let hold = UILongPressGestureRecognizer(target: self, action: #selector(accent(_:)))
                hold.minimumPressDuration = 0.38; key.addGestureRecognizer(hold)
                letterButtons.append(key)
                return key
            }
            if index == 2 {
                let shiftKey = button(capsLock ? "⇪" : "⇧", function: true) { [weak self] in self?.toggleShift() }
                shiftKey.accessibilityLabel = capsLock ? "Caps lock on" : "Shift"
                buttons.insert(shiftKey, at: 0)
                buttons.append(deleteKey())
            }
            row(buttons, inset: index == 1 ? 14 : 0)
        }
    }

    private func buildSymbols() {
        let rows = mode == "numbers" ? ["1234567890", "-/:;()$&@\"", ".,?!'"] : ["[]{}#%^*+=", "_\\|~<>€£¥•", ".,?!'"]
        for (i, characters) in rows.enumerated() {
            var buttons = characters.map { char in button(String(char)) { [weak self] in self?.insert(String(char)) } }
            if i == 2 {
                buttons.insert(button(mode == "numbers" ? "#+=" : "123", function: true) { [weak self] in
                    guard let self else { return }; self.mode = self.mode == "numbers" ? "symbols" : "numbers"; self.rebuildContent()
                }, at: 0)
                buttons.append(deleteKey())
            }
            row(buttons)
        }
    }

    private func buildBottomRow() {
        let stack = UIStackView(); stack.axis = .horizontal; stack.spacing = 5
        let modeKey = button(mode == "letters" ? "123" : "ABC", function: true) { [weak self] in
            guard let self else { return }; self.mode = self.mode == "letters" ? "numbers" : "letters"; self.rebuildContent()
        }
        stack.addArrangedSubview(modeKey)
        let globe = KeyButton(title: "🌐", palette: palette, function: true)
        globe.accessibilityLabel = "Next keyboard"; globe.accessibilityHint = "Hold to select another keyboard"
        globe.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        stack.addArrangedSubview(globe) // Always provide a keyboard switch, including sideloaded builds.
        let comma = button(",") { [weak self] in self?.insert(",") }; stack.addArrangedSubview(comma)
        let space = button(preferences.language.title) { [weak self] in self?.space() }
        space.accessibilityLabel = "Space"; space.accessibilityHint = "Drag to move the cursor"
        let cursor = UIPanGestureRecognizer(target: self, action: #selector(moveCursor(_:))); space.addGestureRecognizer(cursor)
        stack.addArrangedSubview(space)
        let period = button(".") { [weak self] in self?.insert(".") }; stack.addArrangedSubview(period)
        let returnKey = button(returnTitle, function: true) { [weak self] in self?.insert("\n") }
        returnKey.accessibilityLabel = "Return"; stack.addArrangedSubview(returnKey)
        for key in [modeKey, globe, comma, period] { key.widthAnchor.constraint(equalTo: stack.widthAnchor, multiplier: 0.105).isActive = true }
        returnKey.widthAnchor.constraint(equalTo: stack.widthAnchor, multiplier: 0.16).isActive = true
        keys.addArrangedSubview(stack)
    }

    private var returnTitle: String {
        switch textDocumentProxy.returnKeyType ?? .default {
        case .go: return "Go"; case .search: return "Search"; case .send: return "Send"; case .done: return "Done"; case .next: return "Next"; default: return "↵"
        }
    }

    private func deleteKey() -> KeyButton {
        let key = button("⌫", function: true) { [weak self] in self?.delete() }
        key.accessibilityLabel = "Delete"
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(deleteHeld(_:)))
        hold.minimumPressDuration = 0.35; key.addGestureRecognizer(hold)
        return key
    }

    private func insert(_ text: String) {
        correction = nil; glideChoices = []; lastSpace = 0
        textDocumentProxy.insertText(text)
        if shift && !capsLock { shift = false; rebuildContent() }
        if text.hasSuffix("\n") { updateShift() }
        refreshSuggestions()
    }

    private func space() {
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
                  let replacement = engine.autocorrection(for: word, language: preferences.language, protectedWords: protectedWords.union(store.learned.keys), supplemental: supplemental) {
            let record = CorrectionRecord(original: word, replacement: replacement, contextBefore: context)
            replaceCurrentWord(with: replacement)
            textDocumentProxy.insertText(" "); correction = record
        } else {
            correction = nil
            textDocumentProxy.insertText(" ")
            if plainTextField { store.learn(word.lowercased()) }
        }
        glideChoices = []; lastSpace = now; updateShift(); refreshSuggestions()
    }

    private func replaceCurrentWord(with text: String) {
        for _ in currentWord { textDocumentProxy.deleteBackward() }
        textDocumentProxy.insertText(text)
    }

    private func delete() {
        glideChoices = []; lastSpace = 0
        if let correction, correction.canUndo(context: before) {
            for _ in correction.replacement + " " { textDocumentProxy.deleteBackward() }
            textDocumentProxy.insertText(correction.original)
            self.correction = nil
        } else { textDocumentProxy.deleteBackward(); correction = nil }
        updateShift(); refreshSuggestions()
    }

    @objc private func deleteHeld(_ gesture: UILongPressGestureRecognizer) {
        guard let key = gesture.view as? KeyButton else { return }
        if gesture.state == .began {
            key.longPressConsumed = true; delete()
            repeatDelete = Timer.scheduledTimer(withTimeInterval: 0.075, repeats: true) { [weak self] _ in self?.delete() }
        } else if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed {
            repeatDelete?.invalidate(); repeatDelete = nil
            DispatchQueue.main.async { key.longPressConsumed = false }
        }
    }

    private func toggleShift() {
        let now = Date.timeIntervalSinceReferenceDate
        if now - lastShift < 0.3 { capsLock = true; shift = true }
        else if capsLock { capsLock = false; shift = false }
        else { shift.toggle() }
        lastShift = now; rebuildContent()
    }

    private func updateShift(rebuild: Bool = true) {
        guard !capsLock, preferences.autoCapitalization else { return }
        let capitalization = textDocumentProxy.autocapitalizationType ?? .sentences
        let wanted: Bool
        switch capitalization {
        case .none: wanted = false
        case .allCharacters: wanted = true
        case .words: wanted = before.isEmpty || before.last?.isWhitespace == true
        default: wanted = plainTextField && TextContext.shouldCapitalize(after: before)
        }
        if wanted != shift { shift = wanted; if rebuild && panel == nil && mode == "letters" { rebuildContent() } }
    }

    @objc private func moveCursor(_ gesture: UIPanGestureRecognizer) {
        correction = nil; glideChoices = []
        let offset = Int(gesture.translation(in: view).x / 12)
        if offset != 0 { textDocumentProxy.adjustTextPosition(byCharacterOffset: offset); gesture.setTranslation(.zero, in: view) }
        if gesture.state == .ended { updateShift(); refreshSuggestions() }
    }

    private func refreshSuggestions() {
        guard panel == nil else { return }
        suggestionWork?.cancel(); generation += 1
        if let correction, correction.canUndo(context: before) {
            showSuggestions([(correction.original + " ↶", { [weak self] in self?.delete() })]); return
        }
        if !glideChoices.isEmpty && before.hasSuffix(glideSuffix) {
            showSuggestions(glideChoices.map { word in (word, { [weak self] in self?.chooseGlide(word) }) }); return
        }
        guard preferences.predictions && plainTextField else { clear(suggestionBar); setStatus(preferences.language.title); return }
        let word = currentWord, context = before, previous = TextContext.previousWord(in: before)
        let language = preferences.language, learned = store.learned, supplemental = self.supplemental
        let thisGeneration = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            var native: [String] = []
            if language == .english && word.count > 1 && word.count < 32 {
                let range = NSRange(location: 0, length: (word as NSString).length)
                let languageCode = UITextChecker.availableLanguages.contains("en_US") ? "en_US" : "en"
                native = self.checker.completions(forPartialWordRange: range, in: word, language: languageCode) ?? []
                if native.isEmpty { native = self.checker.guesses(forWordRange: range, in: word, language: languageCode) ?? [] }
            }
            let results = self.engine.suggestions(for: word, previous: previous, language: language, learned: learned, supplemental: supplemental + Array(native.prefix(12)))
            DispatchQueue.main.async {
                guard self.generation == thisGeneration, self.before == context, self.panel == nil else { return }
                self.currentSuggestions = results
                var choices: [(String, () -> Void)] = results.map { result in (result.text, { [weak self] in self?.chooseSuggestion(result.text, expectedContext: context) }) }
                if !word.isEmpty { choices.insert((word, { [weak self] in self?.chooseSuggestion(word, expectedContext: context) }), at: 0) }
                self.showSuggestions(Array(choices.prefix(3)))
            }
        }
        suggestionWork = work
        suggestionQueue.asyncAfter(deadline: .now() + 0.04, execute: work)
    }

    private func showSuggestions(_ choices: [(String, () -> Void)]) {
        clear(suggestionBar)
        if choices.isEmpty { setStatus(preferences.language.title); return }
        for (text, action) in choices {
            let key = button(text, action: action)
            key.backgroundColor = .clear; key.normalColor = .clear
            key.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
            key.setTitleColor(palette.accent, for: .normal)
            suggestionBar.addArrangedSubview(key)
        }
    }

    private func chooseSuggestion(_ word: String, expectedContext: String) {
        guard before == expectedContext else { refreshSuggestions(); return }
        replaceCurrentWord(with: word)
        textDocumentProxy.insertText(" ")
        correction = nil; glideChoices = []
        if plainTextField { store.learn(word.lowercased()) }
        updateShift(); refreshSuggestions()
    }

    private func setStatus(_ text: String) {
        clear(suggestionBar)
        let label = UILabel(); label.text = text; label.textColor = palette.accent
        label.font = .systemFont(ofSize: 12, weight: .medium); label.textAlignment = .center
        label.numberOfLines = 2; label.adjustsFontSizeToFitWidth = true
        suggestionBar.addArrangedSubview(label)
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === swipeGesture else { return true }
        guard preferences.swipeTyping, mode == "letters", plainTextField, !UIAccessibility.isVoiceOverRunning else { return false }
        let point = gestureRecognizer.location(in: keys)
        return letterButtons.contains { $0.convert($0.bounds, to: keys).contains(point) }
    }

    @objc private func glide(_ gesture: UIPanGestureRecognizer) {
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
            let choices = decoder.decode(path: glidePath, centers: centers, entries: engine.entries, language: preferences.language, keyWidth: width)
            guard !choices.isEmpty else { setStatus("Swipe a little more slowly, or tap to type"); return }
            glideChoices = choices.map { glideShift ? $0.word.prefix(1).uppercased() + $0.word.dropFirst() : $0.word }
            let prefix = !before.isEmpty && before.last?.isWhitespace == false ? " " : ""
            glideInserted = glideChoices[0]
            textDocumentProxy.insertText(prefix + glideInserted + " ")
            glideSuffix = String(before.suffix(64))
            if glideSuffix.isEmpty { glideChoices = [] }
            if !capsLock { shift = false }
            rebuildContent(); refreshSuggestions()
        } else if gesture.state == .cancelled || gesture.state == .failed { glideLayer.path = nil }
    }

    private func chooseGlide(_ word: String) {
        guard before.hasSuffix(glideSuffix) else { glideChoices = []; refreshSuggestions(); return }
        for _ in glideInserted + " " { textDocumentProxy.deleteBackward() }
        textDocumentProxy.insertText(word + " ")
        glideInserted = word; glideSuffix = String(before.suffix(64)); refreshSuggestions()
    }

    private func accents(for letter: Character) -> [String] {
        let map: [Character: [String]] = ["a":["à", "á", "â", "ä", "ã", "å", "æ"], "e":["ẹ", "ẹ̀", "ẹ́", "è", "é", "ê", "ë"], "i":["ì", "í", "î", "ï"], "o":["ọ", "ọ̀", "ọ́", "ò", "ó", "ô", "ö", "õ"], "u":["ù", "ú", "û", "ü"], "s":["ṣ", "ß"], "n":["ǹ", "ń", "ñ"], "c":["ç"]]
        var values = [String(letter)] + (map[letter] ?? [])
        if let symbol = hints[letter] { values.append(symbol) }
        return (shift || capsLock) ? values.map { $0.uppercased() } : values
    }

    @objc private func accent(_ gesture: UILongPressGestureRecognizer) {
        guard let key = gesture.view as? KeyButton, let letter = key.letter else { return }
        if gesture.state == .began {
            key.longPressConsumed = true
            accentValues = accents(for: letter); accentSelection = 0
            let popup = UIStackView(); popup.axis = .horizontal; popup.distribution = .fillEqually; popup.spacing = 2
            popup.backgroundColor = palette.function; popup.layer.cornerRadius = 8; popup.clipsToBounds = true
            let width = min(content.bounds.width - 8, CGFloat(accentValues.count) * 32)
            let frame = key.convert(key.bounds, to: content)
            popup.frame = CGRect(x: min(max(4, frame.midX - width / 2), content.bounds.width - width - 4), y: max(0, frame.minY - 42), width: width, height: 40)
            for value in accentValues {
                let label = UILabel(); label.text = value; label.textAlignment = .center; label.textColor = palette.text
                label.font = .systemFont(ofSize: 20); popup.addArrangedSubview(label)
            }
            content.addSubview(popup); accentPopup = popup; highlightAccent()
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

    private func highlightAccent() {
        for (i, label) in (accentPopup?.arrangedSubviews ?? []).enumerated() {
            label.backgroundColor = i == accentSelection ? palette.accent.withAlphaComponent(0.3) : .clear
        }
    }
    private func removeAccentPopup() { accentPopup?.removeFromSuperview(); accentPopup = nil }

    private func note(_ text: String, in stack: UIStackView) {
        let label = UILabel(); label.text = text; label.textColor = palette.text.withAlphaComponent(0.8)
        label.font = .systemFont(ofSize: 12); label.numberOfLines = 0; stack.addArrangedSubview(label)
    }
    private func panelButton(_ title: String, in stack: UIStackView, action: @escaping () -> Void) {
        let key = button(title, action: action); key.heightAnchor.constraint(equalToConstant: 36).isActive = true
        key.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium); stack.addArrangedSubview(key)
    }

    private func buildSettings(_ stack: UIStackView) {
        note("Changes here apply immediately. Basic typing works without Full Access.", in: stack)
        panelButton("Language: \(preferences.language.title)", in: stack) { [weak self] in self?.cycleLanguage() }
        for theme in KeyboardTheme.allCases {
            panelButton("\(preferences.theme == theme ? "✓ " : "")\(theme.title)", in: stack) { [weak self] in self?.preferences.theme = theme; self?.savePreferences() }
        }
        for (title, keyPath) in [("Number row", \KeyboardPreferences.numberRow), ("Autocorrect", \KeyboardPreferences.autocorrect), ("Suggestions", \KeyboardPreferences.predictions), ("Swipe typing", \KeyboardPreferences.swipeTyping), ("Auto capitals", \KeyboardPreferences.autoCapitalization), ("Double-space period", \KeyboardPreferences.doubleSpacePeriod), ("Haptic feedback", \KeyboardPreferences.haptics), ("Learn my words locally", \KeyboardPreferences.learnWords)] {
            panelButton("\(preferences[keyPath: keyPath] ? "✓ " : "○ ")\(title)", in: stack) { [weak self] in
                guard let self else { return }; self.preferences[keyPath: keyPath].toggle(); self.savePreferences()
            }
        }
        for hand in HandMode.allCases {
            panelButton("\(preferences.handMode == hand ? "✓ " : "")\(hand.title)", in: stack) { [weak self] in self?.preferences.handMode = hand; self?.savePreferences() }
        }
        for height in [260.0, 300.0, 340.0] {
            panelButton("Height: \(Int(height))", in: stack) { [weak self] in self?.preferences.height = height; self?.savePreferences() }
        }
        panelButton("Clear learned words", in: stack) { [weak self] in self?.store.learned = [:]; self?.setStatus("Learned words cleared") }
        note(store.isShared ? "Settings and phrases are shared with the app." : "Sideloaded builds may keep app and keyboard settings separate. Use these controls for your keyboard.", in: stack)
    }

    private func buildPhrases(_ stack: UIStackView) {
        note("Nothing is saved automatically. Save selected text or explicitly copy from your clipboard.", in: stack)
        panelButton("Save selected text", in: stack) { [weak self] in
            guard let self else { return }
            guard let selected = self.textDocumentProxy.selectedText, !selected.isEmpty else { self.setStatus("Select text in your message first"); return }
            self.store.addPhrase(selected); self.rebuildContent(); self.setStatus("Selection saved on this device")
        }
        panelButton("Save clipboard text", in: stack) { [weak self] in
            guard let self else { return }
            guard self.hasFullAccess else { self.setStatus("Clipboard access needs Allow Full Access in Settings"); return }
            guard let text = UIPasteboard.general.string, !text.isEmpty else { self.setStatus("Your clipboard has no text"); return }
            self.store.addPhrase(text); self.rebuildContent(); self.setStatus("Clipboard text saved")
        }
        let phrases = store.phrases.sorted { $0.pinned == $1.pinned ? $0.createdAt > $1.createdAt : $0.pinned && !$1.pinned }
        if phrases.isEmpty { note("Saved phrases will appear here. You can insert them while offline.", in: stack) }
        for phrase in phrases {
            panelButton((phrase.pinned ? "★ " : "") + String(phrase.text.prefix(65)), in: stack) { [weak self] in self?.insert(phrase.text); self?.showPanel(nil) }
            let controls = UIStackView(); controls.axis = .horizontal; controls.spacing = 8
            controls.addArrangedSubview(button(phrase.pinned ? "Unpin" : "Pin") { [weak self] in
                guard let self else { return }; var items = self.store.phrases
                if let i = items.firstIndex(where: { $0.id == phrase.id }) { items[i].pinned.toggle(); self.store.phrases = items; self.rebuildContent() }
            })
            controls.addArrangedSubview(button("Delete") { [weak self] in self?.store.phrases.removeAll { $0.id == phrase.id }; self?.rebuildContent() })
            controls.heightAnchor.constraint(equalToConstant: 28).isActive = true; stack.addArrangedSubview(controls)
        }
    }

    private func buildEmoji(_ stack: UIStackView) {
        let categories = ["😀 😃 😄 😁 😆 😅 😂 🙂 🙃 😉 😊 😍 🥰 😘 😎 🤔 😭 😢 😡 🤯 😴 🤗 🫶 👍 👎 👏 🙌 🙏 💪 ✌️", "❤️ 🧡 💛 💚 💙 💜 🖤 🤍 💕 💖 💯 🔥 ✨ 🎉 🎊 🎁 🌟 ☀️ 🌙 🌈 🌍 🌺 🌹 🍀 🦋 🐶 🐱 🐣", "🍎 🍉 🍌 🍍 🥑 🍞 🍔 🍕 🍚 🍛 🍗 ☕ 🥤 🧋 ⚽ 🏀 🎵 🎧 📱 💻 ⌨️ 🚗 ✈️ 🏠 💡 💰 ✅ ❌ 🇳🇬"]
        for category in categories {
            let emoji = category.split(separator: " ").map(String.init)
            for start in stride(from: 0, to: emoji.count, by: 8) {
                let row = UIStackView(); row.axis = .horizontal; row.distribution = .fillEqually; row.spacing = 3
                for symbol in emoji[start..<min(start + 8, emoji.count)] { row.addArrangedSubview(button(symbol) { [weak self] in self?.insert(symbol) }) }
                row.heightAnchor.constraint(equalToConstant: 36).isActive = true; stack.addArrangedSubview(row)
            }
        }
        note("Original stickers and GIFs: copy one, then paste it in an app that supports images. Full Access is required to copy media.", in: stack)
        for (title, name, type) in [("Hello sticker", "hello", "png"), ("Thank you sticker", "thanks", "png"), ("Celebration GIF", "celebrate", "gif"), ("Love GIF", "love", "gif")] {
            panelButton(title, in: stack) { [weak self] in
                guard let self else { return }
                guard self.hasFullAccess else { self.setStatus("Turn on Allow Full Access to copy media"); return }
                guard let url = Bundle.main.url(forResource: name, withExtension: type), let data = try? Data(contentsOf: url) else { self.setStatus("Media unavailable"); return }
                UIPasteboard.general.setItems([[type == "gif" ? UTType.gif.identifier : UTType.png.identifier: data]], options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(120)])
                self.setStatus("Copied. Touch and hold your message, then Paste")
            }
        }
    }

    private func buildWriting(_ stack: UIStackView) {
        note("Select text in your message, then choose an action. Only that selection is sent to your configured service. Review the result before replacing it.", in: stack)
        if ConnectionVault.load() == nil {
            note("Connect the optional writing service in the WianTribe app, copy its connection, then import it below. Typing does not need this service.", in: stack)
        }
        panelButton("Import writing connection from clipboard", in: stack) { [weak self] in
            guard let self else { return }
            guard self.hasFullAccess else { self.setStatus("Allow Full Access is needed to import a connection"); return }
            guard let text = UIPasteboard.general.string, let data = text.data(using: .utf8),
                  let connection = try? JSONDecoder().decode(WritingConnection.self, from: data), connection.valid,
                  ConnectionVault.save(connection) else { self.setStatus("Copy a valid connection from the WianTribe app first"); return }
            self.setStatus("Writing service connected"); self.rebuildContent()
        }
        for action in WritingAction.allCases {
            panelButton(action == .translate ? "Translate to \(preferences.language.title)" : action.title, in: stack) { [weak self, weak stack] in
                guard let self, let stack else { return }
                guard self.hasFullAccess else { self.setStatus("Writing tools need Allow Full Access"); return }
                guard let selected = self.textDocumentProxy.selectedText, !selected.isEmpty else { self.setStatus("Select text in your message first"); return }
                self.setStatus("Working…")
                self.onlineTask?.cancel()
                self.onlineTask = Task { @MainActor [weak self, weak stack] in
                    guard let self, let stack else { return }
                    do {
                        let result = try await WritingService.perform(text: selected, action: action, language: self.preferences.language)
                        guard !Task.isCancelled, self.panel == "writing" else { return }
                        self.note(result, in: stack)
                        self.panelButton("Replace selected text with this result", in: stack) { [weak self] in
                            guard let self else { return }
                            guard self.textDocumentProxy.selectedText == selected else { self.setStatus("Selection changed. Select the original text again"); return }
                            self.insert(result); self.showPanel(nil)
                        }
                        self.setStatus("Review the result below")
                    } catch {
                        if !Task.isCancelled { self.setStatus(error.localizedDescription) }
                    }
                }
            }
        }
        panelButton("Disconnect writing service", in: stack) { [weak self] in ConnectionVault.save(nil); self?.rebuildContent(); self?.setStatus("Disconnected") }
        note("Voice typing: open the companion app’s Voice editor, record, then copy your transcript. Apple's dictation button may also be available below the keyboard.", in: stack)
    }
}
