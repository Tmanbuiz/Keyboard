import UIKit
import UniformTypeIdentifiers

enum SearchMode { case emoji, gif }

extension KeyboardViewController {
    /// Panels with their own layout instead of the scrolling list of buttons. Returns false for list panels.
    func buildCustomPanel(_ identifier: String) -> Bool {
        switch identifier {
        case "emoji": buildMediaPanel(); return true
        case "edit": buildEditPanel(); return true
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
        let tabs = UIStackView(); tabs.axis = .horizontal; tabs.spacing = 3
        let scroll = UIScrollView(); scroll.showsHorizontalScrollIndicator = false
        tabs.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(tabs)
        NSLayoutConstraint.activate([tabs.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor), tabs.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
                                     tabs.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor), tabs.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
                                     tabs.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor)])
        func tab(_ title: String, _ label: String, selected: Bool, action: @escaping () -> Void) {
            let key = button(title, function: !selected, action: action)
            key.accessibilityLabel = label
            if selected { key.layer.borderWidth = 1.5; key.layer.borderColor = palette.accent.cgColor }
            key.widthAnchor.constraint(greaterThanOrEqualToConstant: title.count > 2 ? 64 : 40).isActive = true
            tabs.addArrangedSubview(key)
        }
        tab("🔍", "Search emoji", selected: false) { [weak self] in self?.enterSearch(.emoji) }
        tab("🕘", "Recently used", selected: mediaTab == "emoji" && emojiGroup == -1) { [weak self] in self?.mediaTab = "emoji"; self?.emojiGroup = -1; self?.rebuildContent() }
        for group in EmojiCatalog.groups {
            tab(group.icon, group.name, selected: mediaTab == "emoji" && emojiGroup == group.id) { [weak self] in
                self?.mediaTab = "emoji"; self?.emojiGroup = group.id; self?.rebuildContent()
            }
        }
        tab("GIF", "GIFs", selected: mediaTab == "gif") { [weak self] in self?.mediaTab = "gif"; self?.rebuildContent() }
        tab("Stickers", "Stickers", selected: mediaTab == "stickers") { [weak self] in self?.mediaTab = "stickers"; self?.rebuildContent() }
        let backspace = button("⌫", function: true) { [weak self] in self?.textDocumentProxy.deleteBackward() }
        backspace.accessibilityLabel = "Delete"
        backspace.widthAnchor.constraint(equalToConstant: 44).isActive = true
        let header = UIStackView(arrangedSubviews: [scroll, backspace]); header.spacing = 3

        let grid = MediaGridView(palette: palette)
        switch mediaTab {
        case "gif": fillGifs(grid)
        case "stickers": fillStickers(grid)
        default: fillEmoji(grid)
        }
        layoutPanel(header: header, body: grid)
    }

    private func fillEmoji(_ grid: MediaGridView) {
        let catalog = EmojiCatalog.shared, tone = preferences.skinTone
        let list: [EmojiItem]
        if emojiGroup == -1 {
            list = store.recentEmoji.compactMap { emoji in catalog.item(for: emoji).map { $0.skins?.contains(emoji) == true ? EmojiItem(emoji: emoji, group: $0.group, skins: nil) : $0 } }
            if list.isEmpty { emojiGroup = 0; return fillEmoji(grid) }
        } else { list = catalog.items(in: emojiGroup) }
        grid.columns = 8
        grid.items = list.map { .emoji($0.toned(tone), toned: $0.skins != nil) }
        grid.onSelect = { [weak self] index in
            guard let self, list.indices.contains(index) else { return }
            let emoji = list[index].toned(tone)
            self.textDocumentProxy.insertText(emoji); self.store.useEmoji(emoji)
        }
        grid.onLongPress = { [weak self] index, cell in
            guard let self, list.indices.contains(index), let skins = list[index].skins else { return }
            self.showSkinTones([list[index].emoji] + skins, over: cell)
        }
    }

    /// Lets the person pick a skin tone; the choice becomes the default for every emoji that has tones.
    private func showSkinTones(_ options: [String], over cell: UIView) {
        removeAccentPopup()
        let popup = UIStackView(); popup.axis = .horizontal; popup.distribution = .fillEqually; popup.spacing = 2
        popup.backgroundColor = palette.function; popup.layer.cornerRadius = 8; popup.clipsToBounds = true
        for (index, option) in options.enumerated() {
            let key = button(option) { [weak self] in
                guard let self else { return }
                self.removeAccentPopup()
                self.textDocumentProxy.insertText(option); self.store.useEmoji(option)
                self.preferences.skinTone = index
                self.store.preferences = self.preferences
                self.rebuildContent()
            }
            key.titleLabel?.font = .systemFont(ofSize: 26)
            popup.addArrangedSubview(key)
        }
        let width = min(view.bounds.width - 8, CGFloat(options.count) * 44)
        let frame = cell.convert(cell.bounds, to: view)
        popup.frame = CGRect(x: min(max(4, frame.midX - width / 2), view.bounds.width - width - 4), y: max(0, frame.minY - 50), width: width, height: 46)
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
        searchMode = nil
        if let tab { mediaTab = tab; showPanel("emoji") } else { showPanel(nil) }
    }

    func buildSearchToolbar() {
        let close = button("✕", function: true) { [weak self] in self?.exitSearch(returnTo: self?.searchMode == .gif ? "gif" : "emoji") }
        close.accessibilityLabel = "Cancel search"
        close.widthAnchor.constraint(equalToConstant: 44).isActive = true
        let field = UILabel()
        let prompt = searchMode == .gif ? "Search GIFs" : "Search emoji"
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
        guard searchQuery.count < 40 else { return }
        searchQuery += pack.lowercased(text)
        if shift && !capsLock { shift = false; rebuildContent() }
        rebuildToolbar(); refreshSuggestions()
    }

    func searchDelete() {
        guard !searchQuery.isEmpty else { return }
        searchQuery.removeLast()
        rebuildToolbar(); refreshSuggestions()
    }

    func submitSearch() {
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        if searchMode == .gif {
            gifResults = []
            exitSearch(returnTo: "gif")
            loadGifs(query)
        } else { exitSearch(returnTo: "emoji") }
    }

    /// Live emoji results in the suggestion bar as the person types.
    func showSearchResults() {
        clear(suggestionBar)
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
