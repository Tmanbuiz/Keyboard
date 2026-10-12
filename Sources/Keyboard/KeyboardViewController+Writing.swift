import UIKit

struct WritingPreview {
    let source: String
    let isSelection: Bool
    let action: WritingAction
    let language: KeyboardLanguage
    let provider: String
    var text: String
}

extension KeyboardViewController {
    func writingSource() -> (text: String, isSelection: Bool)? {
        if let selected = textDocumentProxy.selectedText, !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return (selected, true) }
        let paragraph = (textDocumentProxy.documentContextBeforeInput ?? "").split(separator: "\n", omittingEmptySubsequences: false).last.map(String.init) ?? ""
        let text = String(paragraph.suffix(3000))
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : (text, false)
    }

    func buildMoreTools(_ stack: UIStackView) {
        for (label, tool) in [("Handwriting", "handwriting"), ("Text editing", "edit"), ("Keyboard settings", "settings"), ("Languages", "languages")] {
            panelButton(label, in: stack) { [weak self] in self?.showPanel(tool) }
        }
    }

    func buildWritingToolbar() {
        toolbar.distribution = .fill
        let back = iconButton("keyboard", label: "Back to keyboard") { [weak self] in self?.showPanel(nil) }
        back.widthAnchor.constraint(equalToConstant: 38).isActive = true
        toolbar.addArrangedSubview(back)
        let title = UILabel()
        title.text = writingPreview.map { writingTitle($0.action) } ?? (panel == "translate" ? "Translate" : (writingStyles ? "Writing style" : "Writing assist"))
        title.textColor = palette.text; title.font = .systemFont(ofSize: KeyButton.fontSize(16), weight: .semibold)
        title.adjustsFontSizeToFitWidth = true; title.minimumScaleFactor = 0.75
        toolbar.addArrangedSubview(title)
        let provider = button(preferences.writingProvider.shortTitle, function: true) {}
        provider.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        provider.widthAnchor.constraint(equalToConstant: 84).isActive = true
        provider.accessibilityLabel = "AI provider: \(preferences.writingProvider.shortTitle)"
        provider.accessibilityIdentifier = "writing-provider-menu"
        provider.menu = writingProviderMenu(); provider.showsMenuAsPrimaryAction = true
        toolbar.addArrangedSubview(provider)
        if needsInputModeSwitchKey {
            let globe = KeyButton(title: "🌐", palette: palette, function: true)
            globe.accessibilityLabel = "Next keyboard"; globe.widthAnchor.constraint(equalToConstant: 38).isActive = true
            globe.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
            toolbar.addArrangedSubview(globe)
        }
    }

    private func writingProviderMenu() -> UIMenu {
        let choices = WritingProvider.allCases.map { provider in
            UIAction(title: provider.title, state: preferences.writingProvider == provider ? .on : .off) { [weak self] _ in
                guard let self else { return }
                self.onlineTask?.cancel(); self.writingRequestID = UUID(); self.writingBusy = false; self.writingStatus = ""
                self.preferences.writingProvider = provider; self.writingPreview = nil; self.savePreferences()
            }
        }
        let importConnection = UIAction(title: "Import AI connection", image: UIImage(systemName: "square.and.arrow.down")) { [weak self] _ in self?.importWritingConnection() }
        let disconnect = UIAction(title: "Disconnect Groq", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
            guard let self else { return }
            self.onlineTask?.cancel(); self.writingRequestID = UUID(); self.writingBusy = false; self.writingPreview = nil
            if GroqVault.save(nil) { self.writingStatus = "Groq key removed from this keyboard." }
            else { self.writingStatus = "Could not remove the Groq key. Try again." }
            self.rebuildToolbar(); self.rebuildContent(); self.setStatus(self.writingStatus)
        }
        let service = UIAction(title: "Disconnect writing service", attributes: .destructive) { [weak self] _ in
            ConnectionVault.save(nil); self?.setWritingStatus("Writing service disconnected.")
        }
        return UIMenu(children: choices.map { $0 as UIMenuElement } + [UIMenu(options: .displayInline, children: [importConnection, disconnect, service])])
    }

    func buildWriting(_ stack: UIStackView) {
        stack.spacing = 8
        if writingBusy {
            let card = writingCard(in: stack)
            let progress = UIActivityIndicatorView(style: .medium); progress.color = palette.accent; progress.startAnimating()
            card.addArrangedSubview(progress)
            note("Working with \(preferences.writingProvider.shortTitle)…", in: card)
            panelButton("Cancel", in: card) { [weak self] in
                guard let self else { return }
                self.onlineTask?.cancel(); self.writingRequestID = UUID(); self.writingBusy = false
                self.setWritingStatus("Request cancelled.")
            }
            return
        }
        if let preview = writingPreview {
            buildWritingResult(preview, in: stack)
            if !writingStatus.isEmpty { note(writingStatus, in: stack) }
            return
        }
        if panel == "translate" {
            note("Select text, or translate the paragraph you just typed.", in: stack)
            buildTranslateRows(stack)
        } else if writingStyles {
            buildWritingStyles(stack)
        } else {
            let primary = writingCard(in: stack)
            let row = UIStackView(); row.axis = .horizontal; row.distribution = .fillEqually; row.spacing = 5
            row.addArrangedSubview(writingActionButton("Spelling and\ngrammar", symbol: "textformat.abc", action: .grammar))
            row.addArrangedSubview(writingMenuButton("Writing style", symbol: "text.bubble") { [weak self] in
                self?.writingStyles = true; self?.rebuildToolbar(); self?.rebuildContent()
            })
            row.addArrangedSubview(writingActionButton("Summarize", symbol: "doc.text", action: .summary))
            row.heightAnchor.constraint(equalToConstant: 76).isActive = true
            primary.addArrangedSubview(row)
            let formats = writingCard(in: stack)
            let second = UIStackView(); second.axis = .horizontal; second.distribution = .fillEqually; second.spacing = 8
            second.addArrangedSubview(writingActionButton("Bullet point", symbol: "list.bullet", action: .bullets, horizontal: true))
            second.addArrangedSubview(writingActionButton("Table", symbol: "tablecells", action: .table, horizontal: true))
            second.heightAnchor.constraint(equalToConstant: 44).isActive = true
            formats.addArrangedSubview(second)
            let composer = writingCard(in: stack)
            let compose = writingActionButton("Composer", symbol: "square.and.pencil", action: .compose, horizontal: true)
            compose.heightAnchor.constraint(equalToConstant: 44).isActive = true
            composer.addArrangedSubview(compose)
        }
        if !writingStatus.isEmpty { note(writingStatus, in: stack) }
        note(preferences.writingProvider == .groq
             ? "Powered by your Groq account. Select text first; for Composer, type what you want to say."
             : "Select text or use your current paragraph. For Composer, type a topic or a request first.", in: stack)
        buildServiceRows(stack)
    }

    private func writingCard(in stack: UIStackView) -> UIStackView {
        let card = WritingCardView(palette: palette)
        let inner = UIStackView(); inner.axis = .vertical; inner.spacing = 10; inner.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
            inner.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),
            inner.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
            inner.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -10)
        ])
        stack.addArrangedSubview(card)
        return inner
    }

    private func writingMenuButton(_ title: String, symbol: String, horizontal: Bool = false, action: @escaping () -> Void) -> KeyButton {
        let key = button("", action: action)
        // KeyButton uses legacy title states for character keys. Keep the AI label
        // in its own view so an empty legacy title cannot hide Configuration.title.
        let icon = UIImageView(image: UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .regular)))
        icon.tintColor = palette.text; icon.contentMode = .scaleAspectFit
        icon.widthAnchor.constraint(equalToConstant: 22).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 22).isActive = true
        let label = UILabel(); label.text = title; label.textColor = palette.text
        label.font = .systemFont(ofSize: KeyButton.fontSize(horizontal ? 15 : 13), weight: .medium)
        label.textAlignment = .center; label.numberOfLines = horizontal ? 1 : 2
        label.adjustsFontSizeToFitWidth = true; label.minimumScaleFactor = 0.75; label.isAccessibilityElement = false
        let group = UIStackView(arrangedSubviews: [icon, label]); group.axis = horizontal ? .horizontal : .vertical
        group.alignment = .center; group.spacing = horizontal ? 8 : 10
        group.isUserInteractionEnabled = false; group.translatesAutoresizingMaskIntoConstraints = false
        key.addSubview(group)
        NSLayoutConstraint.activate([group.centerXAnchor.constraint(equalTo: key.centerXAnchor), group.centerYAnchor.constraint(equalTo: key.centerYAnchor),
            group.leadingAnchor.constraint(greaterThanOrEqualTo: key.leadingAnchor, constant: 2),
            group.trailingAnchor.constraint(lessThanOrEqualTo: key.trailingAnchor, constant: -2),
            group.topAnchor.constraint(greaterThanOrEqualTo: key.topAnchor, constant: 4),
            group.bottomAnchor.constraint(lessThanOrEqualTo: key.bottomAnchor, constant: -4)])
        key.normalColor = .clear; key.backgroundColor = .clear
        key.layer.borderWidth = 0; key.layer.shadowOpacity = 0
        key.accessibilityLabel = title.replacingOccurrences(of: "\n", with: " ")
        return key
    }

    private func writingActionButton(_ title: String, symbol: String, action: WritingAction, horizontal: Bool = false) -> KeyButton {
        let key = writingMenuButton(title, symbol: symbol, horizontal: horizontal) { [weak self] in self?.runWriting(action, target: self?.preferences.language ?? .english) }
        key.accessibilityIdentifier = "writing-action-\(action.rawValue)"
        return key
    }

    private func buildWritingStyles(_ stack: UIStackView) {
        let card = writingCard(in: stack)
        let actions = WritingAction.rewrites.filter { $0 != .grammar } + [.email]
        for start in stride(from: 0, to: actions.count, by: 2) {
            let row = UIStackView(); row.axis = .horizontal; row.distribution = .fillEqually; row.spacing = 8
            for action in actions[start..<min(start + 2, actions.count)] {
                row.addArrangedSubview(writingActionButton(action.title, symbol: "text.alignleft", action: action, horizontal: true))
            }
            row.heightAnchor.constraint(equalToConstant: 42).isActive = true
            card.addArrangedSubview(row)
        }
        panelButton("All writing tools", in: stack) { [weak self] in self?.writingStyles = false; self?.rebuildToolbar(); self?.rebuildContent() }
    }

    private func buildWritingResult(_ preview: WritingPreview, in stack: UIStackView) {
        let card = writingCard(in: stack)
        let text = UILabel(); text.numberOfLines = 0; text.text = preview.text
        text.font = .systemFont(ofSize: KeyButton.fontSize(17)); text.textColor = palette.text
        text.accessibilityIdentifier = "writing-result"
        card.addArrangedSubview(text)
        let actions = UIStackView(); actions.axis = .horizontal; actions.distribution = .fillEqually; actions.spacing = 5
        let edit = writingMenuButton("Edit", symbol: "pencil", horizontal: true) { [weak self] in self?.startWritingEdit() }
        let copy = writingMenuButton("Copy", symbol: "doc.on.doc", horizontal: true) { [weak self] in
            guard let self, let text = self.writingPreview?.text else { return }
            self.copyToClipboard(text); self.setWritingStatus("Result copied.")
        }
        let replace = writingMenuButton("Replace", symbol: "arrow.triangle.2.circlepath", horizontal: true) { [weak self] in self?.replaceWritingResult() }
        replace.accessibilityIdentifier = "replace-writing-result"
        copy.isEnabled = hasFullAccess
        for key in [edit, copy, replace] { actions.addArrangedSubview(key) }
        actions.heightAnchor.constraint(equalToConstant: 40).isActive = true
        card.addArrangedSubview(actions)
        note("\(preview.provider) · Review the text before replacing it.", in: stack)
        panelButton("Try again", in: stack) { [weak self] in
            guard let self else { return }
            self.runWriting(preview.action, target: preview.language)
        }
        panelButton("All writing tools", in: stack) { [weak self] in
            self?.writingPreview = nil; self?.writingStyles = false; self?.writingStatus = ""
            self?.rebuildToolbar(); self?.rebuildContent(); self?.updateTopBar()
        }
    }

    func buildTranslateRows(_ stack: UIStackView) {
        let card = writingCard(in: stack)
        var targets = preferences.activeLanguages
        if !targets.contains(.english) { targets.append(.english) }
        for target in targets.prefix(6) {
            let key = writingMenuButton("Translate to \(target.pack.englishName)", symbol: "translate", horizontal: true) { [weak self] in self?.runWriting(.translate, target: target) }
            key.heightAnchor.constraint(equalToConstant: 40).isActive = true
            card.addArrangedSubview(key)
        }
    }

    func buildServiceRows(_ stack: UIStackView) {
        let configured = preferences.writingProvider == .groq ? GroqVault.load() != nil : ConnectionVault.load() != nil
        if !configured && preferences.writingProvider != .apple {
            panelButton("Import AI connection", in: stack) { [weak self] in self?.importWritingConnection() }
            note("Open WianTribe → Tools → AI setup to save your Groq key, then copy its connection here.", in: stack)
        }
    }

    private func importWritingConnection() {
        guard hasFullAccess else { setWritingStatus("Enable Allow Full Access in iPhone Keyboard settings, then import your connection."); return }
        let count = UIPasteboard.general.changeCount
        guard let text = UIPasteboard.general.string, let data = text.data(using: .utf8), data.count < 16_000 else {
            setWritingStatus("Copy the AI connection from WianTribe → Tools → AI setup first."); return
        }
        if let transfer = try? JSONDecoder().decode(WritingConnectionTransfer.self, from: data), transfer.install() {
            preferences.writingProvider = transfer.provider
        } else if let legacy = try? JSONDecoder().decode(WritingConnection.self, from: data), legacy.valid, ConnectionVault.save(legacy) {
            preferences.writingProvider = .service
        } else { setWritingStatus("This is not a valid AI connection. Copy it from AI setup in the WianTribe app."); return }
        if UIPasteboard.general.changeCount == count { UIPasteboard.general.items = [] }
        onlineTask?.cancel(); writingRequestID = UUID(); writingBusy = false; writingPreview = nil
        writingStatus = "\(preferences.writingProvider.shortTitle) connected and selected."
        savePreferences(); setStatus(writingStatus)
    }

    func runWriting(_ action: WritingAction, target: KeyboardLanguage) {
        guard let source = writingSource() else { setWritingStatus(action == .compose ? "Type what you want to say in the app first, then tap Composer." : "Type or select some text first."); return }
        onlineTask?.cancel()
        let requestID = UUID(); writingRequestID = requestID
        writingBusy = true; writingStatus = ""; writingPreview = nil
        rebuildContent(); updateTopBar()
        let provider = preferences.writingProvider
        onlineTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let output = try await WritingRouter.perform(text: source.text, action: action, language: target, provider: provider, allowOnline: self.hasFullAccess)
                guard !Task.isCancelled, self.writingRequestID == requestID, self.panel == "writing" || self.panel == "translate" else { return }
                self.writingBusy = false; self.writingStatus = ""
                self.writingPreview = WritingPreview(source: source.text, isSelection: source.isSelection, action: action, language: target, provider: output.provider, text: output.text)
                self.rebuildToolbar(); self.rebuildContent(); self.updateTopBar()
            } catch {
                guard !Task.isCancelled, self.writingRequestID == requestID else { return }
                self.writingBusy = false; self.setWritingStatus(error.localizedDescription)
            }
        }
    }

    private func setWritingStatus(_ text: String) {
        writingStatus = text; setStatus(text); rebuildContent(); updateTopBar()
    }

    private func writingTitle(_ action: WritingAction) -> String {
        switch action {
        case .grammar: return "Spelling and grammar"
        case .summary: return "Summarize"
        case .bullets: return "Bullet point"
        default: return action.title
        }
    }

    private func replaceWritingResult() {
        guard let preview = writingPreview else { return }
        if preview.isSelection {
            guard textDocumentProxy.selectedText == preview.source else { setWritingStatus("The selection changed. Select the original text and try again."); return }
        } else {
            guard (textDocumentProxy.documentContextBeforeInput ?? "").hasSuffix(preview.source) else { setWritingStatus("The original text changed. Run the writing tool again."); return }
            for _ in preview.source { textDocumentProxy.deleteBackward() }
        }
        textDocumentProxy.insertText(preview.text); showPanel(nil)
    }

    private func startWritingEdit() {
        guard let preview = writingPreview else { return }
        writingEditBuffer = WritingEditBuffer(text: preview.text); writingEditing = true
        panel = nil; writingStatus = ""; updateShift(rebuild: false)
        rebuildToolbar(); rebuildContent(); updateTopBar()
    }

    func finishWritingEdit(save: Bool) {
        if save { writingPreview?.text = writingEditBuffer.text }
        writingEditing = false; writingEditBuffer = WritingEditBuffer(text: "")
        panel = writingPreview?.action == .translate ? "translate" : "writing"
        rebuildToolbar(); rebuildContent(); updateTopBar()
    }

    func buildWritingEditToolbar() {
        toolbar.distribution = .fill
        let cancel = button("Cancel", function: true) { [weak self] in self?.finishWritingEdit(save: false) }
        cancel.widthAnchor.constraint(equalToConstant: 64).isActive = true; toolbar.addArrangedSubview(cancel)
        let title = UILabel(); title.text = "Edit result"; title.textAlignment = .center
        title.font = .systemFont(ofSize: 15, weight: .semibold); title.textColor = palette.text
        toolbar.addArrangedSubview(title)
        let done = button("Done", function: true) { [weak self] in self?.finishWritingEdit(save: true) }
        done.widthAnchor.constraint(equalToConstant: 64).isActive = true; toolbar.addArrangedSubview(done)
    }

    func buildWritingEditPreview() {
        let text = UITextView(); text.translatesAutoresizingMaskIntoConstraints = false
        text.isEditable = false; text.isSelectable = false
        text.backgroundColor = palette.key; text.layer.cornerRadius = 12
        text.font = .systemFont(ofSize: 15); text.textColor = palette.text
        text.textContainerInset = UIEdgeInsets(top: 9, left: 10, bottom: 9, right: 10)
        text.accessibilityLabel = "AI result being edited"; text.accessibilityIdentifier = "writing-edit-preview"
        content.addSubview(text); writingEditTextView = text
        NSLayoutConstraint.activate([text.leadingAnchor.constraint(equalTo: content.leadingAnchor), text.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            text.topAnchor.constraint(equalTo: content.topAnchor), text.heightAnchor.constraint(equalToConstant: 54)])
        refreshWritingEditPreview()
    }

    func refreshWritingEditPreview() {
        guard let view = writingEditTextView else { return }
        let text = NSMutableAttributedString(string: writingEditBuffer.before + "▏" + writingEditBuffer.after,
            attributes: [.font: UIFont.systemFont(ofSize: 15), .foregroundColor: palette.text])
        let position = (writingEditBuffer.before as NSString).length
        text.addAttribute(.foregroundColor, value: palette.accent, range: NSRange(location: position, length: 1))
        view.attributedText = text
        view.scrollRangeToVisible(NSRange(location: position, length: 1))
    }
}

private final class WritingCardView: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }
    init(palette: KeyboardPalette) {
        super.init(frame: .zero)
        layer.cornerRadius = 22; layer.cornerCurve = .continuous; layer.masksToBounds = true
        let gradient = layer as! CAGradientLayer
        gradient.colors = [palette.key.cgColor, palette.key.cgColor, palette.accent.withAlphaComponent(0.12).cgColor]
        gradient.startPoint = CGPoint(x: 0, y: 0); gradient.endPoint = CGPoint(x: 1, y: 1)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
}
