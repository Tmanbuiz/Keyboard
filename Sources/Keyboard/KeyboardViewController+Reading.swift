import UIKit

/// iOS shows a keyboard only a few sentences around the cursor, and a long selection arrives as its first
/// line and last sentence with the middle missing. To work on a whole message, the keyboard moves the cursor
/// through the text box, reads it a piece at a time and puts the cursor back. This runs only when the person
/// taps a writing tool, Copy or Cut, and nothing read here is stored.
extension KeyboardViewController {
    /// The text box around the cursor, as read.
    struct FieldText: Equatable {
        var before: [Character]
        var after: [Character]

        /// True when `other` shows the same text, comparing as much as both reads hold, and the text right
        /// before the cursor is unchanged for at least `count` characters.
        func agrees(with other: FieldText, covering count: Int) -> Bool {
            let back = min(before.count, other.before.count), ahead = min(after.count, other.after.count)
            return back >= count && before.suffix(back).elementsEqual(other.before.suffix(back))
                && after.prefix(ahead).elementsEqual(other.after.prefix(ahead))
        }
    }

    /// Text a tool works on, found in the text box. The cursor sits right after it.
    struct TextSpot {
        var field: FieldText
        /// Length of the text, in characters, ending at the cursor.
        var length: Int
        var readsAfter: Bool
        /// How far reads go each way; 0 when iOS didn't follow cursor moves and only its own view was used.
        var limit: Int
        var text: String { String(field.before.suffix(length)) }
    }

    /// Moves the cursor by `offset` UTF-16 units, then waits until iOS reports the text at the new position.
    func moveCursor(by offset: Int) async -> Bool {
        guard offset != 0 else { return true }
        let proxy = textDocumentProxy
        let oldBefore = proxy.documentContextBeforeInput, oldAfter = proxy.documentContextAfterInput
        proxy.adjustTextPosition(byCharacterOffset: offset)
        for _ in 0 ..< 50 {
            try? await Task.sleep(nanoseconds: 10_000_000)
            if proxy.documentContextBeforeInput != oldBefore || proxy.documentContextAfterInput != oldAfter { return true }
        }
        return false
    }

    /// Reads from the cursor back to the start of the text box (and on to its end when `readsAfter`), up to
    /// `limit` characters each way, then puts the cursor back. Nil when iOS didn't follow the cursor.
    func readField(limit: Int, readsAfter: Bool) async -> FieldText? {
        readingText = true
        defer { readingText = false }
        let proxy = textDocumentProxy
        let startWindow = proxy.documentContextBeforeInput ?? ""
        var before = "", after = "", followed = true
        var moved = 0
        while before.count < limit {
            let chunk = proxy.documentContextBeforeInput ?? ""
            if chunk.isEmpty { break }
            before = chunk + before
            if before.count >= limit { break }
            moved += chunk.utf16.count
            guard await moveCursor(by: -chunk.utf16.count) else { followed = false; break }
        }
        if moved > 0 { _ = await moveCursor(by: moved) }
        if followed && readsAfter {
            var movedAhead = 0
            while after.count < limit {
                let chunk = proxy.documentContextAfterInput ?? ""
                if chunk.isEmpty { break }
                after += chunk
                if after.count >= limit { break }
                movedAhead += chunk.utf16.count
                guard await moveCursor(by: chunk.utf16.count) else { followed = false; break }
            }
            if movedAhead > 0 { _ = await moveCursor(by: -movedAhead) }
        }
        // Back where it started: iOS shows the same text before the cursor as at the start.
        guard followed, !Task.isCancelled, (proxy.documentContextBeforeInput ?? "") == startWindow else { return nil }
        return FieldText(before: Array(before), after: Array(after))
    }

    /// Turns the selection into a cursor right next to it, because iOS gives no way to read a long selection.
    func collapseSelection(_ selected: String) async -> Bool {
        readingText = true
        defer { readingText = false }
        let proxy = textDocumentProxy
        // Apps differ on whether a move starts from the selection's start or its end, so one of these lands
        // the cursor next to it.
        var steps: [Int] = []
        if let next = (proxy.documentContextAfterInput ?? "").first { steps.append(String(next).utf16.count) }
        if let last = selected.last { steps.append(-String(last).utf16.count) }
        if let first = selected.first { steps.append(String(first).utf16.count) }
        for step in steps {
            proxy.adjustTextPosition(byCharacterOffset: step)
            for _ in 0 ..< 40 {
                try? await Task.sleep(nanoseconds: 10_000_000)
                if proxy.selectedText?.isEmpty != false { return true }
            }
        }
        return false
    }

    /// Finds the whole of a selection iOS may have shortened. The selection becomes a cursor at its end.
    func readSelection(_ selected: String) async -> TextSpot? {
        let proxy = textDocumentProxy
        let windowBefore = proxy.documentContextBeforeInput ?? "", windowAfter = proxy.documentContextAfterInput ?? ""
        let limit = 8000
        guard await collapseSelection(selected), let field = await readField(limit: limit, readsAfter: true) else { return nil }
        let all = field.before + field.after, caret = field.before.count
        guard let range = SelectionText.locate(selected: selected, before: windowBefore, after: windowAfter, in: all, caret: caret) else { return nil }
        // Put the cursor right after the selection, where Replace and Cut work from.
        let distance = range.upperBound >= caret
            ? String(all[caret ..< range.upperBound]).utf16.count
            : -String(all[range.upperBound ..< caret]).utf16.count
        readingText = true
        let moved = await moveCursor(by: distance)
        readingText = false
        guard moved else { return nil }
        return TextSpot(field: FieldText(before: Array(all[..<range.upperBound]), after: Array(all[range.upperBound...])),
                        length: range.count, readsAfter: true, limit: limit)
    }

    /// The message typed before the cursor, read whole: its last `limit` Unicode scalars at most.
    func readTypedText(limit: Int) async -> TextSpot? {
        guard let field = await readField(limit: limit + 500, readsAfter: false) else { return nil }
        let part = SelectionText.recentPart(of: String(field.before), limit: limit)
        // Spaces and line breaks before the message stay where they are.
        let length = part.drop { $0.isWhitespace }.count
        return TextSpot(field: field, length: length, readsAfter: false, limit: limit + 500)
    }

    /// Replaces the text of `spot` with `replacement` after checking the text box still shows the same text
    /// around the cursor. Returns false, changing nothing, when it doesn't.
    func replace(_ spot: TextSpot, with replacement: String) async -> Bool {
        let now: FieldText?
        if spot.limit > 0 { now = await readField(limit: spot.limit, readsAfter: spot.readsAfter) }
        else { now = FieldText(before: Array(textDocumentProxy.documentContextBeforeInput ?? ""), after: []) }
        guard let now, textDocumentProxy.selectedText?.isEmpty != false,
              now.agrees(with: spot.field, covering: spot.length) else { return false }
        for _ in 0 ..< spot.length { textDocumentProxy.deleteBackward() }
        if !replacement.isEmpty { textDocumentProxy.insertText(replacement) }
        return true
    }

    /// Runs `use` with the whole selected text, reading it from the text box when iOS may have shortened it.
    func useWholeSelection(_ selected: String, _ use: @escaping @MainActor (String) -> Void) {
        guard SelectionText.mayBeShortened(selected) else { use(selected); return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let spot = await self.readSelection(selected) else { self.setStatus("Couldn't read all of this selection. Use the app's own menu instead"); return }
            use(spot.text)
        }
    }
}
