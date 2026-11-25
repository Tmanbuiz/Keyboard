import Foundation

/// iOS shows a keyboard only part of the text it works on. A selection of several lines arrives as its
/// first line and last sentence, with everything between them missing (seen in Messages and Mail), and the
/// text before and after the cursor is cut to a few sentences. These helpers decide when a selection can be
/// trusted as reported, and find the whole selection in text the keyboard read by moving the cursor.
public enum SelectionText {
    /// Longest selection taken as reported. Longer ones are read from the text box.
    static let trustedLength = 200

    /// True when iOS may have shortened `selected`: it is long, spans lines, or holds more than one sentence.
    public static func mayBeShortened(_ selected: String) -> Bool {
        selected.count > trustedLength || selected.contains(where: \.isNewline) || hasSentenceBreak(selected)
    }

    /// A sentence end (. ! ? … and the Arabic, Urdu, Chinese and Japanese forms) with more text after it.
    static func hasSentenceBreak(_ text: String) -> Bool {
        let ends: Set<Character> = [".", "!", "?", "…", "؟", "۔", "。", "！", "？"]
        let spaceless: Set<Character> = ["。", "！", "？"]
        let closers: Set<Character> = ["\"", "'", "”", "’", ")", "]", "»"]
        let chars = Array(text)
        var index = 0
        while index < chars.count {
            guard ends.contains(chars[index]) else { index += 1; continue }
            var next = index + 1
            // Quotes, brackets and repeated marks stay with the sentence they end.
            while next < chars.count, closers.contains(chars[next]) || ends.contains(chars[next]) { next += 1 }
            let restHasText = next < chars.count && chars[next...].contains { !$0.isWhitespace }
            if restHasText && chars[next].isWhitespace { return true }
            // Chinese and Japanese put no space after a sentence.
            if restHasText && spaceless.contains(chars[index]) { return true }
            index = next
        }
        return false
    }

    /// Finds the whole selection in `text`, the text box as read by moving the cursor.
    /// - Parameters:
    ///   - selected: what iOS reported as selected, possibly only its start and end
    ///   - before: what iOS reported just before the selection (shortened, and empty at the start of the box)
    ///   - after: what iOS reported just after it
    ///   - caret: where the cursor is in `text` (in characters) once the selection became a cursor, which
    ///     is right next to the selection's start or end
    /// - Returns: the selection's range in `text`, or nil unless exactly one place fits.
    public static func locate(selected: String, before: String, after: String, in text: [Character], caret: Int) -> Range<Int>? {
        let selection = Array(selected)
        guard !selection.isEmpty, !text.isEmpty else { return nil }
        // First with what iOS showed around the selection, then, in case an app reports that differently,
        // with the cursor's position alone.
        return find(selection, in: text, caret: caret, before: Array(before), after: Array(after))
            ?? find(selection, in: text, caret: caret, before: [], after: [])
    }

    private static func find(_ selection: [Character], in text: [Character], caret: Int, before: [Character], after: [Character]) -> Range<Int>? {
        func fits(_ start: Int, _ end: Int) -> Bool {
            start < end && (abs(caret - start) <= 2 || abs(caret - end) <= 2)
                && text[..<start].suffix(before.count).elementsEqual(before) && text[end...].prefix(after.count).elementsEqual(after)
        }
        // The selection exactly as reported, when iOS gave all of it.
        let whole = occurrences(of: selection, in: text).map { $0 ..< $0 + selection.count }.filter { fits($0.lowerBound, $0.upperBound) }
        if whole.count == 1 { return whole[0] }
        if whole.count > 1 { return nil }
        // Otherwise its start and its end: iOS keeps the beginning of the first line and the end of the last.
        // Shorter pieces are tried when a longer one runs into the place where iOS joined the two parts.
        let firstLine = Array(selection.prefix { !$0.isNewline })
        let lastLine = Array(selection.reversed().prefix { !$0.isNewline }.reversed())
        let headSource = firstLine.isEmpty ? selection : firstLine
        let tailSource = lastLine.isEmpty ? selection : lastLine
        for headLength in [24, 12, 6, 3] {
            let head = Array(headSource.prefix(headLength))
            let starts = occurrences(of: head, in: text)
            if starts.isEmpty { continue }
            for tailLength in [24, 12, 6, 3] {
                let tail = Array(tailSource.suffix(tailLength))
                let ends = occurrences(of: tail, in: text).map { $0 + tail.count }
                var found: [Range<Int>] = []
                for start in starts {
                    for end in ends where end - start >= max(head.count, tail.count) && fits(start, end) {
                        found.append(start ..< end)
                    }
                }
                if found.count == 1 { return found[0] }
                if found.count > 1 { return nil }
            }
        }
        return nil
    }

    static func occurrences(of part: [Character], in text: [Character]) -> [Int] {
        guard !part.isEmpty, part.count <= text.count else { return [] }
        var found: [Int] = []
        for start in 0 ... (text.count - part.count) where text[start] == part[0] {
            var index = 1
            while index < part.count && text[start + index] == part[index] { index += 1 }
            if index == part.count { found.append(start) }
        }
        return found
    }

    /// The end of `text` that a writing tool may send: at most `limit` Unicode scalars, starting after a
    /// line break when one leaves most of that room used, or else at a word, so nothing is cut mid-word.
    public static func recentPart(of text: String, limit: Int) -> String {
        guard text.unicodeScalars.count > limit else { return text }
        var start = text.endIndex, used = 0
        while start > text.startIndex {
            let previous = text.index(before: start)
            let size = text[previous].unicodeScalars.count
            if used + size > limit { break }
            used += size; start = previous
        }
        let part = text[start...]
        if let lineBreak = part.firstIndex(where: \.isNewline),
           part.distance(from: lineBreak, to: part.endIndex) > part.count * 2 / 3 {
            return String(part[part.index(after: lineBreak)...])
        }
        if let space = part.firstIndex(where: \.isWhitespace) { return String(part[part.index(after: space)...]) }
        return String(part)
    }

    /// The result with the spaces and line breaks that began and ended the original, so the text around a
    /// replacement doesn't run into it.
    public static func keepingOuterSpace(of original: String, _ result: String) -> String {
        let leading = String(original.prefix { $0.isWhitespace })
        let trailing = String(original.reversed().prefix { $0.isWhitespace }.reversed())
        var text = result
        if !leading.isEmpty && !(text.first?.isWhitespace ?? false) { text = leading + text }
        if !trailing.isEmpty && !(text.last?.isWhitespace ?? false) { text += trailing }
        return text
    }
}
