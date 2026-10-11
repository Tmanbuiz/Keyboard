import UIKit

extension KeyboardViewController {
    // MARK: Text editing panel

    func buildEditPanel() {
        let grid = UIStackView(); grid.axis = .vertical; grid.spacing = 5; grid.distribution = .fillEqually
        func row(_ keys: [KeyButton]) {
            let line = UIStackView(arrangedSubviews: keys); line.axis = .horizontal; line.spacing = 5; line.distribution = .fillEqually
            grid.addArrangedSubview(line)
        }
        row([repeating("◀︎", label: "Left") { [weak self] in self?.moveCharacters(-1) },
             repeating("▲", label: "Line up") { [weak self] in self?.moveLines(-1) },
             repeating("▶︎", label: "Right") { [weak self] in self?.moveCharacters(1) }])
        row([repeating("⇠ word", label: "Previous word") { [weak self] in self?.moveWords(-1) },
             repeating("▼", label: "Line down") { [weak self] in self?.moveLines(1) },
             repeating("word ⇢", label: "Next word") { [weak self] in self?.moveWords(1) }])
        row([editKey("⇤ Line start") { [weak self] in self?.moveToLineEdge(start: true) },
             editKey("Line end ⇥") { [weak self] in self?.moveToLineEdge(start: false) },
             repeating("⌫ word", label: "Delete word") { [weak self] in self?.deleteWord() }])
        row([editKey("Copy") { [weak self] in self?.copySelectionOrStatus(cut: false) },
             editKey("Cut") { [weak self] in self?.copySelectionOrStatus(cut: true) },
             editKey("Paste") { [weak self] in self?.pasteClipboard() },
             editKey("Done", function: true) { [weak self] in self?.showPanel(nil) }])
        layoutPanel(header: nil, body: grid)
        setStatus("Select text in the app, then Copy or Cut here")
    }

    private func editKey(_ title: String, function: Bool = false, action: @escaping () -> Void) -> KeyButton {
        let key = button(title, function: function, action: action)
        key.titleLabel?.font = .systemFont(ofSize: KeyButton.fontSize(15), weight: .medium)
        return key
    }

    /// A key that repeats while held, like Samsung's cursor arrows.
    private func repeating(_ title: String, label: String, action: @escaping () -> Void) -> KeyButton {
        let key = editKey(title, action: action)
        key.accessibilityLabel = label
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(repeatHeld(_:)))
        hold.minimumPressDuration = 0.35
        key.addGestureRecognizer(hold)
        return key
    }

    @objc func repeatHeld(_ gesture: UILongPressGestureRecognizer) {
        guard let key = gesture.view as? KeyButton else { return }
        if gesture.state == .began {
            key.longPressConsumed = true; key.onTap?()
            repeatDelete = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in key.onTap?() }
        } else if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed {
            repeatDelete?.invalidate(); repeatDelete = nil
            DispatchQueue.main.async { key.longPressConsumed = false }
        }
    }

    func moveCharacters(_ offset: Int) {
        correction = nil; glideChoices = []
        // Move by whole characters so emoji and accented letters are not split.
        if offset < 0, let last = (textDocumentProxy.documentContextBeforeInput ?? "").last {
            textDocumentProxy.adjustTextPosition(byCharacterOffset: -String(last).utf16.count)
        } else if offset > 0, let next = (textDocumentProxy.documentContextAfterInput ?? "").first {
            textDocumentProxy.adjustTextPosition(byCharacterOffset: String(next).utf16.count)
        }
    }

    func moveWords(_ direction: Int) {
        correction = nil; glideChoices = []
        if direction < 0 {
            let text = textDocumentProxy.documentContextBeforeInput ?? ""
            let trailingSpaces = text.reversed().prefix { !TextContext.isWordCharacter($0) }
            let word = String(text.dropLast(trailingSpaces.count).reversed().prefix(while: TextContext.isWordCharacter))
            let distance = (String(trailingSpaces) + word).utf16.count
            if distance > 0 { textDocumentProxy.adjustTextPosition(byCharacterOffset: -distance) }
        } else {
            let text = textDocumentProxy.documentContextAfterInput ?? ""
            let leading = text.prefix { !TextContext.isWordCharacter($0) }
            let word = text.dropFirst(leading.count).prefix(while: TextContext.isWordCharacter)
            let distance = (String(leading) + String(word)).utf16.count
            if distance > 0 { textDocumentProxy.adjustTextPosition(byCharacterOffset: distance) }
        }
    }

    /// iOS gives keyboards no line geometry, so up/down move to the same column in the previous or next line of text.
    func moveLines(_ direction: Int) {
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        let after = textDocumentProxy.documentContextAfterInput ?? ""
        let currentLine = before.split(separator: "\n", omittingEmptySubsequences: false).last.map(String.init) ?? ""
        let column = currentLine.utf16.count
        if direction < 0 {
            let lines = before.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            guard lines.count > 1 else { textDocumentProxy.adjustTextPosition(byCharacterOffset: -column); return }
            let previous = lines[lines.count - 2].utf16.count
            textDocumentProxy.adjustTextPosition(byCharacterOffset: -(column + 1 + max(0, previous - column)))
        } else {
            let lines = after.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            let rest = lines.first?.utf16.count ?? 0
            guard lines.count > 1 else { textDocumentProxy.adjustTextPosition(byCharacterOffset: rest); return }
            textDocumentProxy.adjustTextPosition(byCharacterOffset: rest + 1 + min(column, lines[1].utf16.count))
        }
    }

    func moveToLineEdge(start: Bool) {
        if start {
            let line = (textDocumentProxy.documentContextBeforeInput ?? "").split(separator: "\n", omittingEmptySubsequences: false).last ?? ""
            if !line.isEmpty { textDocumentProxy.adjustTextPosition(byCharacterOffset: -String(line).utf16.count) }
        } else {
            let line = (textDocumentProxy.documentContextAfterInput ?? "").split(separator: "\n", omittingEmptySubsequences: false).first ?? ""
            if !line.isEmpty { textDocumentProxy.adjustTextPosition(byCharacterOffset: String(line).utf16.count) }
        }
    }

    func deleteWord() {
        let text = textDocumentProxy.documentContextBeforeInput ?? ""
        let spaces = text.reversed().prefix { $0 == " " }.count
        let word = text.dropLast(spaces).reversed().prefix(while: TextContext.isWordCharacter).count
        let count = max(1, spaces + word)
        for _ in 0..<count { textDocumentProxy.deleteBackward() }
        correction = nil; glideChoices = []
    }

    func copySelectionOrStatus(cut: Bool) {
        guard let selected = textDocumentProxy.selectedText, !selected.isEmpty else { setStatus("Select text first: double-tap a word in the app"); return }
        guard hasFullAccess else { setStatus("Copy and paste need Allow Full Access"); return }
        copyToClipboard(selected)
        if cut { textDocumentProxy.deleteBackward(); setStatus("Cut. Paste it anywhere") }
    }

    func pasteClipboard() {
        guard hasFullAccess else { setStatus("Paste needs Allow Full Access"); return }
        guard let text = UIPasteboard.general.string, !text.isEmpty else { setStatus("Your clipboard has no text"); return }
        textDocumentProxy.insertText(text)
    }
}
