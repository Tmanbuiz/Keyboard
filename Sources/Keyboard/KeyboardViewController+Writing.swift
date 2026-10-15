import UIKit

/// The AI writing panel: a menu of tools in rounded cards, then a result card with Copy and Replace.
extension KeyboardViewController {
    func buildWritingPanel() {
        let body = UIScrollView(); body.showsVerticalScrollIndicator = false
        let stack = UIStackView(); stack.axis = .vertical; stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        body.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: body.contentLayoutGuide.leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: body.contentLayoutGuide.trailingAnchor, constant: -6),
            stack.topAnchor.constraint(equalTo: body.contentLayoutGuide.topAnchor, constant: 2),
            stack.bottomAnchor.constraint(equalTo: body.contentLayoutGuide.bottomAnchor, constant: -6),
            stack.widthAnchor.constraint(equalTo: body.frameLayoutGuide.widthAnchor, constant: -12)])
        var header: UIView?
        if let action = writingAction {
            header = writingHeader(action == .translate ? "Translate to \(writingTarget?.pack.englishName ?? "")" : action.title) { [weak self] in
                guard let self else { return }
                self.onlineTask?.cancel(); self.writingAction = nil; self.writingResult = nil; self.writingError = nil
                self.rebuildContent()
            }
            buildWritingResult(stack, action)
        } else if panel == "translate" {
            buildTranslateMenu(stack)
        } else if writingStyleMenu {
            header = writingHeader("Writing style") { [weak self] in self?.writingStyleMenu = false; self?.rebuildContent() }
            buildStyleMenu(stack)
        } else {
            buildAssistMenu(stack)
        }
        layoutPanel(header: header, body: body)
    }

    // MARK: Pieces

    func writingTile(_ title: String, symbol: String?, horizontal: Bool = false, action: @escaping () -> Void) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.title = title
        if let symbol { config.image = UIImage(systemName: symbol) }
        config.imagePlacement = horizontal ? .leading : .top
        config.imagePadding = horizontal ? 8 : 4
        config.baseForegroundColor = palette.text
        config.titleAlignment = .center
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 4, bottom: 6, trailing: 4)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = .systemFont(ofSize: KeyButton.fontSize(horizontal ? 15 : 13), weight: .medium)
            return attributes
        }
        let tile = UIButton(configuration: config)
        tile.addAction(UIAction { [weak self] _ in self?.feedback(); action() }, for: .touchUpInside)
        tile.accessibilityLabel = title
        return tile
    }

    /// A rounded card holding tiles side by side, with thin dividers between them.
    func writingCard(_ tiles: [UIView], height: CGFloat) -> UIView {
        let card = UIView()
        card.backgroundColor = palette.key.withAlphaComponent(0.7)
        card.layer.cornerRadius = height > 60 ? 18 : height / 2
        card.layer.cornerCurve = .continuous
        card.clipsToBounds = true
        let row = UIStackView(); row.axis = .horizontal; row.alignment = .fill; row.distribution = .fill
        row.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(row)
        NSLayoutConstraint.activate([row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 6), row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -6),
                                     row.topAnchor.constraint(equalTo: card.topAnchor), row.bottomAnchor.constraint(equalTo: card.bottomAnchor)])
        for (index, tile) in tiles.enumerated() {
            if index > 0 {
                let divider = UIView(); divider.backgroundColor = palette.text.withAlphaComponent(0.18)
                divider.translatesAutoresizingMaskIntoConstraints = false
                let holder = UIView(); holder.addSubview(divider); holder.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([holder.widthAnchor.constraint(equalToConstant: 1), divider.widthAnchor.constraint(equalToConstant: 1),
                                             divider.centerYAnchor.constraint(equalTo: holder.centerYAnchor), divider.heightAnchor.constraint(equalTo: holder.heightAnchor, multiplier: 0.6),
                                             divider.leadingAnchor.constraint(equalTo: holder.leadingAnchor)])
                row.addArrangedSubview(holder)
            }
            row.addArrangedSubview(tile)
            if index > 0 { tile.widthAnchor.constraint(equalTo: tiles[0].widthAnchor).isActive = true }
        }
        card.heightAnchor.constraint(equalToConstant: height).isActive = true
        return card
    }

    func writingHeader(_ title: String, back: @escaping () -> Void) -> UIView {
        let row = UIStackView(); row.axis = .horizontal; row.spacing = 6; row.alignment = .center
        let backButton = UIButton(type: .system)
        backButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        backButton.tintColor = palette.text; backButton.accessibilityLabel = "Back"
        backButton.addAction(UIAction { [weak self] _ in self?.feedback(); back() }, for: .touchUpInside)
        backButton.widthAnchor.constraint(equalToConstant: 36).isActive = true
        let icon = UIImageView(image: UIImage(systemName: "sparkles")); icon.tintColor = palette.accent
        icon.setContentHuggingPriority(.required, for: .horizontal)
        let label = UILabel(); label.text = title; label.textColor = palette.text
        label.font = .systemFont(ofSize: KeyButton.fontSize(16), weight: .semibold); label.adjustsFontSizeToFitWidth = true
        [backButton, icon, label].forEach(row.addArrangedSubview)
        return row
    }

    func caption(_ text: String, in stack: UIStackView) {
        let label = UILabel(); label.text = text; label.textColor = palette.text.withAlphaComponent(0.7)
        label.font = .systemFont(ofSize: 12); label.numberOfLines = 0; label.textAlignment = .center
        stack.addArrangedSubview(label)
    }

    // MARK: Menus

    func buildAssistMenu(_ stack: UIStackView) {
        let go: (WritingAction) -> Void = { [weak self] action in
            guard let self else { return }
            self.runWritingAssist(action, target: self.preferences.language)
        }
        stack.addArrangedSubview(writingCard([writingTile("Chat translation", symbol: "translate", horizontal: true) { [weak self] in self?.showPanel("translate") }], height: 44))
        stack.addArrangedSubview(writingCard([
            writingTile("Spelling and grammar", symbol: "textformat.abc") { go(.grammar) },
            writingTile("Writing style", symbol: "pencil.line") { [weak self] in self?.writingStyleMenu = true; self?.rebuildContent() },
            writingTile("Summarize", symbol: "doc.text") { go(.summary) }], height: 80))
        stack.addArrangedSubview(writingCard([
            writingTile("Bullet point", symbol: "list.bullet", horizontal: true) { go(.bullets) },
            writingTile("Table", symbol: "tablecells", horizontal: true) { go(.table) },
            writingTile("Email", symbol: "envelope", horizontal: true) { go(.email) }], height: 44))
        let onDevice = OnDeviceWriting.canRewrite && preferences.aiEngine == .auto
        note("Works on selected text, or on what you've typed in this paragraph. " + (onDevice
             ? "Runs on this iPhone with Apple Intelligence when your language is supported."
             : "Uses your WianTribe service, because Apple Intelligence isn't available here."), in: stack)
        buildServiceRows(stack)
    }

    func buildStyleMenu(_ stack: UIStackView) {
        let styles = WritingAction.rewrites.filter { $0 != .grammar }
        for start in stride(from: 0, to: styles.count, by: 2) {
            let tiles = styles[start..<min(start + 2, styles.count)].map { action in
                writingTile(action.title, symbol: nil, horizontal: true) { [weak self] in
                    guard let self else { return }
                    self.runWritingAssist(action, target: self.preferences.language)
                }
            }
            stack.addArrangedSubview(writingCard(tiles, height: 44))
        }
    }

    func buildTranslateMenu(_ stack: UIStackView) {
        // Every language can be a target: the person's own languages first, then the rest A to Z.
        let mine = preferences.activeLanguages.map(\.pack)
        let others = LanguageCatalog.all.filter { pack in !mine.contains { $0.code == pack.code } }.sorted { $0.englishName < $1.englishName }
        var packs = mine + others
        // Don't offer the language the text is already in.
        if let text = writingSource()?.text, let detected = OnDeviceWriting.detectLanguage(text) {
            let base = Locale.Language(identifier: detected).languageCode
            packs = packs.filter { Locale.Language(identifier: $0.primaryLanguage).languageCode != base }
        }
        note("Translate to:", in: stack)
        for start in stride(from: 0, to: packs.count, by: 3) {
            let tiles = packs[start..<min(start + 3, packs.count)].map { pack in
                writingTile(pack.englishName, symbol: nil, horizontal: true) { [weak self] in self?.runWritingAssist(.translate, target: KeyboardLanguage(pack.code)) }
            }
            // Keep a short last row the same width as the others.
            var row = tiles
            while row.count < 3 { row.append(UIView()) }
            stack.addArrangedSubview(writingCard(row, height: 48))
        }
        note("Works on selected text, or on what you've typed in this paragraph. Translation runs on this iPhone once the languages are downloaded in the WianTribe app.", in: stack)
        buildServiceRows(stack)
    }

    // MARK: Result

    func buildWritingResult(_ stack: UIStackView, _ action: WritingAction) {
        let card = UIView(); card.backgroundColor = palette.key.withAlphaComponent(0.7)
        card.layer.cornerRadius = 18; card.layer.cornerCurve = .continuous
        let label = UILabel(); label.numberOfLines = 0; label.textColor = palette.text
        label.font = .systemFont(ofSize: KeyButton.fontSize(16))
        if let result = writingResult { label.text = result }
        else if let error = writingError { label.text = error; label.textColor = palette.text.withAlphaComponent(0.75) }
        else { label.text = "Working…"; label.textColor = palette.text.withAlphaComponent(0.6) }
        label.translatesAutoresizingMaskIntoConstraints = false; card.addSubview(label)
        let actions = UIStackView(); actions.axis = .horizontal; actions.spacing = 4; actions.distribution = .fillEqually
        actions.translatesAutoresizingMaskIntoConstraints = false; card.addSubview(actions)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: card.topAnchor, constant: 14), label.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            actions.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 8), actions.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -6),
            actions.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10), actions.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),
            actions.heightAnchor.constraint(equalToConstant: 36)])
        if let result = writingResult, let source = writingSourceText {
            actions.addArrangedSubview(writingTile("Copy", symbol: nil, horizontal: true) { [weak self] in
                guard let self else { return }
                guard self.hasFullAccess else { self.setStatus("Allow Full Access is needed to copy"); return }
                UIPasteboard.general.string = result; self.setStatus("Copied")
            })
            actions.addArrangedSubview(writingTile("Insert", symbol: nil, horizontal: true) { [weak self] in
                guard let self else { return }
                guard self.textDocumentProxy.selectedText?.isEmpty != false else {
                    self.setStatus("Move the cursor outside the selection to insert without replacing it"); return
                }
                self.textDocumentProxy.insertText(result); self.showPanel(nil)
            })
            actions.addArrangedSubview(writingTile("Replace", symbol: nil, horizontal: true) { [weak self] in
                guard let self else { return }
                guard self.textDocumentProxy.documentIdentifier == self.writingDocumentID else {
                    self.setStatus("The text field changed. Run the writing tool again"); return
                }
                if source.isSelection {
                    guard self.textDocumentProxy.selectedText == source.text else { self.setStatus("Selection changed. Select the original text again"); return }
                } else {
                    guard self.textDocumentProxy.selectedText?.isEmpty != false, self.before.hasSuffix(source.text) else { self.setStatus("The text changed. Try again"); return }
                    for _ in source.text { self.textDocumentProxy.deleteBackward() }
                }
                self.textDocumentProxy.insertText(result)
                self.writingUndo = (source.text, result, self.textDocumentProxy.documentIdentifier)
                self.showPanel(nil)
            })
            stack.addArrangedSubview(writingCard([
                writingTile("Edit", symbol: "pencil", horizontal: true) { [weak self] in
                    guard let self else { return }
                    self.enterSearch(.writing); self.searchQuery = result
                    self.rebuildToolbar(); self.refreshSuggestions()
                }], height: 44))
        } else if writingError != nil {
            actions.addArrangedSubview(writingTile("Try again", symbol: nil, horizontal: true) { [weak self] in
                guard let self, let target = self.writingTarget else { return }
                self.runWritingAssist(action, target: target)
            })
        }
        stack.addArrangedSubview(card)
        caption(writingResult != nil ? "Result \(writingVia)." : (writingError != nil ? "Request stopped. Your text has not been changed." : (action == .translate ? "Translating…" : "Working…")), in: stack)
    }

    /// Tries Apple's on-device models first, then the person's own service.
    func runWritingAssist(_ action: WritingAction, target: KeyboardLanguage) {
        guard let source = writingSource() else { setStatus("Type or select some text first"); return }
        onlineTask?.cancel()
        writingAction = action; writingTarget = target; writingResult = nil; writingError = nil
        writingDocumentID = textDocumentProxy.documentIdentifier
        writingSourceText = source; writingVia = "on this iPhone"
        rebuildContent()
        onlineTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var result: String?, via = "on this iPhone", failure: Error?
            let useApple = self.preferences.aiEngine == .auto
            if !useApple && ConnectionVault.load() == nil {
                self.finishWriting(action, nil, via, "Sign in: WianTribe app → Tools → AI account"); return
            }
            if useApple { do {
                if action == .translate {
                    do { result = try await OnDeviceWriting.translate(source.text, to: target) }
                    catch let error as OnDeviceError {
                        // Apple's translation can be missing in a keyboard or a language pack not downloaded:
                        // let the on-device language model translate instead when it knows the language.
                        if case .sameLanguage = error { throw error }
                        guard OnDeviceWriting.supportsRewrite(language: target.code) else { throw error }
                        result = try await OnDeviceWriting.rewrite(source.text, action: .translate, language: target)
                    }
                }
                else if OnDeviceWriting.supportsRewrite(language: self.preferences.language.code) {
                    result = try await OnDeviceWriting.rewrite(source.text, action: action, language: target)
                }
            } catch { failure = error } }
            if result == nil, ConnectionVault.load() != nil {
                guard self.hasFullAccess else { self.finishWriting(action, nil, via, "Your service needs Allow Full Access"); return }
                do { result = try await WritingService.perform(text: source.text, action: action, language: target); via = "by your service" }
                catch { failure = error }
            }
            self.finishWriting(action, result, via, failure?.localizedDescription ?? "Sign in in WianTribe → Tools → AI account")
        }
    }

    private func finishWriting(_ action: WritingAction, _ result: String?, _ via: String, _ message: String) {
        guard !Task.isCancelled, panel == "writing" || panel == "translate", writingAction == action else { return }
        writingResult = result; writingVia = via; writingError = result == nil ? message : nil
        rebuildContent()
    }
}
