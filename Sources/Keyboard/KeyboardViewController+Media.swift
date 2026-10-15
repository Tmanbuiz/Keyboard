import UIKit
import UniformTypeIdentifiers

enum SearchMode { case emoji, gif, writing, clips }

extension KeyboardViewController {
    /// Panels with their own layout instead of the scrolling list of buttons. Returns false for list panels.
    func buildCustomPanel(_ identifier: String) -> Bool {
        switch identifier {
        case "emoji": buildMediaPanel(); return true
        case "edit": buildEditPanel(); return true
        case "writing", "translate": buildWritingPanel(); return true
        case "handwriting": buildHandwritingPanel(); return true
        default: return false
        }
    }

    /// Fills `content` with a fixed header row and a view that takes the remaining height.
    func layoutPanel(header: UIView?, body: UIView) {
        let stack = UIStackView(arrangedSubviews: [header, body].compactMap { $0 })
        stack.axis = .vertical; stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: content.leadingAnchor), stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                                     stack.topAnchor.constraint(equalTo: content.topAnchor), stack.bottomAnchor.constraint(equalTo: content.bottomAnchor)])
        header?.heightAnchor.constraint(equalToConstant: 34).isActive = true
    }

    // MARK: Emoji, GIFs and stickers

    func buildMediaPanel() {
        let body = UIStackView(); body.axis = .vertical; body.spacing = 4
        let keyboard = button("ABC", function: true) { [weak self] in self?.showPanel(nil) }
        keyboard.accessibilityLabel = "Back to keyboard"
        let emoji = button("Emoji", function: mediaTab != "emoji") { [weak self] in self?.mediaTab = "emoji"; self?.rebuildContent() }
        let gif = button("GIF", function: mediaTab != "gif") { [weak self] in self?.mediaTab = "gif"; self?.rebuildContent() }
        let stickers = button("Stickers", function: mediaTab != "stickers") { [weak self] in self?.mediaTab = "stickers"; self?.rebuildContent() }
        let backspace = button("⌫", function: true) { [weak self] in self?.textDocumentProxy.deleteBackward() }
        backspace.accessibilityLabel = "Delete"
        let modeRow = UIStackView(arrangedSubviews: [keyboard, emoji, gif, stickers, backspace])
        modeRow.distribution = .fillEqually; modeRow.spacing = 4
        modeRow.heightAnchor.constraint(equalToConstant: 34).isActive = true
        body.addArrangedSubview(modeRow)

        if mediaTab == "emoji" {
            let rail = UIScrollView(); rail.showsHorizontalScrollIndicator = false
            let categories = UIStackView(); categories.axis = .horizontal; categories.distribution = .fillEqually; categories.spacing = 1
            categories.translatesAutoresizingMaskIntoConstraints = false; rail.addSubview(categories)
            NSLayoutConstraint.activate([
                categories.leadingAnchor.constraint(equalTo: rail.contentLayoutGuide.leadingAnchor), categories.trailingAnchor.constraint(equalTo: rail.contentLayoutGuide.trailingAnchor),
                categories.topAnchor.constraint(equalTo: rail.contentLayoutGuide.topAnchor), categories.bottomAnchor.constraint(equalTo: rail.contentLayoutGuide.bottomAnchor),
                categories.heightAnchor.constraint(equalTo: rail.frameLayoutGuide.heightAnchor),
                categories.widthAnchor.constraint(greaterThanOrEqualTo: rail.frameLayoutGuide.widthAnchor), rail.heightAnchor.constraint(equalToConstant: 36)])
            func category(_ title: String, label: String, selected: Bool = false, action: @escaping () -> Void) {
                let key = button(title, function: !selected, action: action)
                key.accessibilityLabel = label; key.accessibilityTraits = selected ? [.button, .selected] : .button
                key.titleLabel?.font = .systemFont(ofSize: 21)
                key.widthAnchor.constraint(greaterThanOrEqualToConstant: 29).isActive = true
                if selected { key.layer.borderWidth = 1.5; key.layer.borderColor = palette.accent.cgColor }
                categories.addArrangedSubview(key)
            }
            category("⌕", label: "Search emoji") { [weak self] in self?.enterSearch(.emoji) }
            category("◷", label: "Recently used", selected: emojiGroup == -1 && emojiQuery.isEmpty) { [weak self] in
                self?.emojiGroup = -1; self?.emojiQuery = ""; self?.rebuildContent()
            }
            for group in EmojiCatalog.groups {
                category(group.icon, label: group.name, selected: emojiGroup == group.id && emojiQuery.isEmpty) { [weak self] in
                    self?.emojiGroup = group.id; self?.emojiQuery = ""; self?.rebuildContent()
                }
            }
            body.addArrangedSubview(rail)
            let heading = UILabel(); heading.textColor = palette.text.withAlphaComponent(0.7)
            heading.font = .systemFont(ofSize: 12, weight: .medium)
            heading.text = emojiQuery.isEmpty ? (emojiGroup == -1 ? "RECENTLY USED" : EmojiCatalog.groups.first { $0.id == emojiGroup }?.name.uppercased()) : "RESULTS FOR “\(emojiQuery)” · tap a category to clear"
            heading.heightAnchor.constraint(equalToConstant: 19).isActive = true
            body.addArrangedSubview(heading)
        }
        let grid = MediaGridView(palette: palette)
        switch mediaTab {
        case "gif": fillGifs(grid)
        case "stickers": fillStickers(grid)
        default: fillEmoji(grid)
        }
        body.addArrangedSubview(grid)
        layoutPanel(header: nil, body: body)
    }

    private func fillEmoji(_ grid: MediaGridView) {
        let catalog = EmojiCatalog.shared, tone = preferences.skinTone
        let list: [EmojiItem]
        if !emojiQuery.isEmpty {
            list = catalog.search(emojiQuery, languages: preferences.activeLanguages.map(\.code), limit: 500)
        } else if emojiGroup == -1 {
            list = store.recentEmoji.compactMap { emoji in catalog.item(for: emoji).map { $0.availableVariants.contains(emoji) ? EmojiItem(emoji: emoji, group: $0.group, skins: nil, version: $0.version, name: $0.name) : $0 } }
            // Empty recents stays empty instead of silently switching categories.
        } else { list = catalog.items(in: emojiGroup) }
        grid.adaptiveEmojiColumns = true
        grid.items = list.map { .emoji($0.toned(tone), toned: !$0.availableVariants.isEmpty, name: $0.name) }
        grid.emptyMessage = emojiQuery.isEmpty ? "Your recently used emoji will appear here" : "No emoji found. Try another word or category."
        grid.onSelect = { [weak self] index in
            guard let self, list.indices.contains(index) else { return }
            let emoji = list[index].toned(tone)
            self.textDocumentProxy.insertText(emoji); self.store.useEmoji(emoji)
        }
        grid.onLongPress = { [weak self] index, cell in
            guard let self, list.indices.contains(index) else { return }
            let item = list[index]
            guard !item.availableVariants.isEmpty else { return }
            self.showSkinTones([item.emoji] + item.availableVariants, defaultSkins: item.skins ?? [], over: cell)
        }
    }

    /// Lets the person pick a skin tone; the choice becomes the default for every emoji that has tones.
    private func showSkinTones(_ options: [String], defaultSkins: [String], over cell: UIView) {
        removeAccentPopup()
        let popup = UIStackView(); popup.axis = .vertical; popup.spacing = 2
        popup.backgroundColor = palette.function; popup.layer.cornerRadius = 12; popup.clipsToBounds = true
        let scroll = UIScrollView(); scroll.showsVerticalScrollIndicator = true
        let rows = UIStackView(); rows.axis = .vertical; rows.spacing = 2; rows.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(rows); popup.addArrangedSubview(scroll)
        NSLayoutConstraint.activate([rows.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor), rows.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
                                     rows.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor), rows.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
                                     rows.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor)])
        let columns = min(6, options.count)
        for start in stride(from: 0, to: options.count, by: columns) {
            let row = UIStackView(); row.axis = .horizontal; row.spacing = 2; row.distribution = .fillEqually
            row.heightAnchor.constraint(equalToConstant: 44).isActive = true
            for offset in 0..<columns {
                guard start + offset < options.count else { row.addArrangedSubview(UIView()); continue }
                let option = options[start + offset]
                let key = button(option) { [weak self] in
                    guard let self else { return }
                    self.removeAccentPopup(); self.textDocumentProxy.insertText(option); self.store.useEmoji(option)
                    if option == options.first { self.preferences.skinTone = 0 }
                    else if let index = defaultSkins.firstIndex(of: option) { self.preferences.skinTone = index + 1 }
                    self.store.preferences = self.preferences; self.rebuildContent()
                }
                key.titleLabel?.font = .systemFont(ofSize: 29)
                row.addArrangedSubview(key)
            }
            rows.addArrangedSubview(row)
        }
        let width = min(view.bounds.width - 8, CGFloat(columns) * 46)
        let height = min(view.bounds.height - 16, CGFloat((options.count + columns - 1) / columns) * 46)
        let frame = cell.convert(cell.bounds, to: view)
        popup.frame = CGRect(x: min(max(4, frame.midX - width / 2), view.bounds.width - width - 4),
                             y: min(max(4, frame.minY - height), view.bounds.height - height - 4), width: width, height: height)
        view.addSubview(popup); accentPopup = popup
    }

    private func fillStickers(_ grid: MediaGridView) {
        let media = Self.stickerFiles()
        grid.columns = 4
        grid.items = media.compactMap { file in
            guard let url = Bundle.main.url(forResource: file.name, withExtension: file.type), let image = UIImage(contentsOfFile: url.path) else { return nil }
            return .image(image, label: file.title)
        }
        grid.onSelect = { [weak self] index in
            guard let self, media.indices.contains(index) else { return }
            self.copyMedia(name: media[index].name, type: media[index].type)
        }
        setStatus(hasFullAccess ? "Tap a sticker to copy it, then paste it in your chat" : "Turn on Allow Full Access to copy stickers")
    }

    static func stickerFiles() -> [(name: String, type: String, title: String)] {
        let urls = (Bundle.main.urls(forResourcesWithExtension: "png", subdirectory: nil) ?? []) + (Bundle.main.urls(forResourcesWithExtension: "gif", subdirectory: nil) ?? [])
        return urls.map { url -> (String, String, String) in
            let name = url.deletingPathExtension().lastPathComponent
            return (name, url.pathExtension, name.replacingOccurrences(of: "sticker-", with: "").replacingOccurrences(of: "-", with: " ").capitalized)
        }
        .filter { $0.0.hasPrefix("sticker-") || ["hello", "thanks", "celebrate", "love"].contains($0.0) }
        .sorted { $0.0 < $1.0 }
    }

    func copyMedia(name: String, type: String) {
        guard hasFullAccess else { setStatus("Turn on Allow Full Access to copy media"); return }
        guard let url = Bundle.main.url(forResource: name, withExtension: type), let data = try? Data(contentsOf: url) else { setStatus("Media unavailable"); return }
        copyImageData(data, gif: type == "gif")
    }

    func copyImageData(_ data: Data, gif: Bool) {
        UIPasteboard.general.setItems([[gif ? UTType.gif.identifier : UTType.png.identifier: data]], options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(300)])
        store.lastChangeCount = UIPasteboard.general.changeCount
        setStatus("Copied. Touch and hold your message, then Paste")
    }

    private func fillGifs(_ grid: MediaGridView) {
        grid.columns = 3
        guard hasFullAccess else { setStatus("GIFs need Allow Full Access in Settings"); return }
        guard GifService.isConfigured else {
            setStatus("Connect your WianTribe service in the app to search GIFs"); return
        }
        let results = gifResults
        grid.items = results.map { .remoteImage($0.preview, label: $0.title ?? "GIF") }
        grid.onSelect = { [weak self] index in
            guard let self, results.indices.contains(index) else { return }
            self.setStatus("Copying GIF…")
            self.gifTask?.cancel()
            self.gifTask = Task { @MainActor [weak self] in
                do {
                    let data = try await GifService.download(results[index])
                    guard !Task.isCancelled else { return }
                    self?.copyImageData(data, gif: true)
                } catch { self?.setStatus(error.localizedDescription) }
            }
        }
        if results.isEmpty { loadGifs("") } else { setStatus("Powered by GIPHY · tap a GIF to copy it") }
    }

    func loadGifs(_ query: String) {
        gifTask?.cancel()
        setStatus(query.isEmpty ? "Loading trending GIFs…" : "Searching “\(query)”…")
        gifTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let results = try await GifService.search(query, language: self.preferences.language.code)
                guard !Task.isCancelled else { return }
                self.gifResults = results
                if self.panel == "emoji" && self.mediaTab == "gif" { self.rebuildContent() }
                if results.isEmpty { self.setStatus("No GIFs found. Try other words") }
            } catch { if !Task.isCancelled { self.setStatus(error.localizedDescription) } }
        }
    }

    // MARK: In-keyboard search

    func enterSearch(_ mode: SearchMode) {
        searchMode = mode; searchQuery = ""
        panel = nil; self.mode = "letters"; shift = false; capsLock = false
        rebuildToolbar(); rebuildContent(); refreshSuggestions()
    }

    func exitSearch(returnTo tab: String? = nil) {
        if searchMode == .writing {
            searchMode = nil; panel = writingAction == .translate ? "translate" : "writing"
            rebuildToolbar(); rebuildContent(); return
        }
        if searchMode == .clips { searchMode = nil; showPanel("clips"); return }
        searchMode = nil
        if let tab { mediaTab = tab; showPanel("emoji") } else { showPanel(nil) }
    }

    func buildSearchToolbar() {
        let close = button("✕", function: true) { [weak self] in self?.exitSearch(returnTo: self?.searchMode == .gif ? "gif" : "emoji") }
        close.accessibilityLabel = "Cancel search"
        close.widthAnchor.constraint(equalToConstant: 44).isActive = true
        let field = UILabel()
        let prompt = searchMode == .writing ? "Edit result" : (searchMode == .clips ? "Search clipboard" : (searchMode == .gif ? "Search GIFs" : "Search emoji"))
        field.lineBreakMode = .byTruncatingHead
        field.text = searchQuery.isEmpty ? "🔍 \(prompt)" : "🔍 \(searchQuery)▏"
        field.textColor = searchQuery.isEmpty ? palette.text.withAlphaComponent(0.55) : palette.text
        field.font = .systemFont(ofSize: 15); field.backgroundColor = palette.key
        field.layer.cornerRadius = 7; field.clipsToBounds = true
        field.accessibilityLabel = searchQuery.isEmpty ? prompt : "Searching \(searchQuery)"
        let padded = UIStackView(arrangedSubviews: [field]); padded.isLayoutMarginsRelativeArrangement = true
        toolbar.distribution = .fill
        toolbar.addArrangedSubview(close); toolbar.addArrangedSubview(padded)
    }

    func searchInput(_ text: String) {
        guard text != "\n" else { submitSearch(); return }
        let editing = searchMode == .writing
        guard searchQuery.count + text.count <= (editing ? 6000 : 40) else { return }
        searchQuery += editing ? (shift || capsLock ? pack.uppercased(text) : text) : pack.lowercased(text)
        if shift && !capsLock { shift = false; rebuildContent() }
        rebuildToolbar(); refreshSuggestions()
    }

    func searchDelete() {
        guard !searchQuery.isEmpty else { return }
        searchQuery.removeLast()
        rebuildToolbar(); refreshSuggestions()
    }

    func submitSearch() {
        if searchMode == .writing {
            guard !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { setStatus("The result cannot be empty"); return }
            writingResult = searchQuery; exitSearch(); return
        }
        if searchMode == .clips { clipQuery = searchQuery; exitSearch(); return }
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        if searchMode == .gif {
            gifResults = []
            exitSearch(returnTo: "gif")
            loadGifs(query)
        } else { emojiQuery = query; exitSearch(returnTo: "emoji") }
    }

    /// Live emoji results in the suggestion bar as the person types.
    func showSearchResults() {
        clear(suggestionBar)
        if searchMode == .writing { setStatus("Edit the end of the result · Done saves · ✕ cancels"); return }
        if searchMode == .clips { setStatus("Type a phrase, then tap Done"); return }
        guard searchMode == .emoji else {
            setStatus(searchQuery.isEmpty ? "Type what you're looking for, then tap Search" : "Tap Search to find “\(searchQuery)” GIFs"); return
        }
        guard !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty else { setStatus("Type to search, e.g. “happy” or “cat”"); return }
        let languages = preferences.activeLanguages.map(\.code)
        let results = EmojiCatalog.shared.search(searchQuery, languages: languages, limit: 40)
        guard !results.isEmpty else { setStatus("No emoji for “\(searchQuery)”"); return }
        let scroll = UIScrollView(); scroll.showsHorizontalScrollIndicator = false
        let row = UIStackView(); row.axis = .horizontal; row.spacing = 2
        row.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(row)
        NSLayoutConstraint.activate([row.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor), row.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
                                     row.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor), row.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
                                     row.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor)])
        for item in results {
            let emoji = item.toned(preferences.skinTone)
            let key = button(emoji) { [weak self] in self?.textDocumentProxy.insertText(emoji); self?.store.useEmoji(emoji) }
            key.backgroundColor = .clear; key.normalColor = .clear; key.layer.shadowOpacity = 0
            key.titleLabel?.font = .systemFont(ofSize: 24)
            key.widthAnchor.constraint(equalToConstant: 38).isActive = true
            row.addArrangedSubview(key)
        }
        suggestionBar.addArrangedSubview(scroll)
    }
}
