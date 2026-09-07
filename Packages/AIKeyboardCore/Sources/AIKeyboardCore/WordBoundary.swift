import Foundation

enum WordBoundary {
    static func staysInsideWord(_ character: Character) -> Bool {
        "'’-\u{05BE}\u{05F3}\u{05F4}\u{00B7}\u{200C}".contains(character)
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || staysInsideWord(character)
    }

    private static func isOpaque(_ text: String) -> Bool {
        text.contains("@") || text.contains("://") || text.hasPrefix("www.")
            || (text.contains(where: \.isNumber)
                && text.allSatisfy { $0.isNumber || "+-().,".contains($0) })
    }

    static func prefix(in text: String) -> String {
        guard let last = text.last, !last.isWhitespace else { return "" }
        let chunk = String(text.reversed().prefix { !$0.isWhitespace }.reversed())
        if isOpaque(String(chunk)) { return String(chunk) }
        var start = chunk.startIndex
        var sawWord = false
        var crossedBoundary = false
        for index in chunk.indices {
            if isWordCharacter(chunk[index]) {
                if crossedBoundary { start = index }
                sawWord = true
                crossedBoundary = false
            } else if sawWord {
                crossedBoundary = true
            }
        }
        if let last = chunk.last, !last.isPunctuation, !isWordCharacter(last) { return "" }
        return String(chunk[start...])
    }

    static func continuation(in text: String) -> String {
        guard let first = text.first, isWordCharacter(first) else { return "" }
        let chunk = text.prefix { !$0.isWhitespace }
        if isOpaque(String(chunk)) { return String(chunk) }
        return String(chunk.prefix(while: isWordCharacter))
    }

    static func continuesBeforeCursor(in text: String) -> Bool {
        let before = text.reversed().drop(while: staysInsideWord)
        guard let last = before.first else { return false }
        return last.isLetter || last.isNumber
    }

    static func continuesAfterCursor(in text: String) -> Bool {
        let after = text.drop(while: staysInsideWord)
        guard let first = after.first else { return false }
        return first.isLetter || first.isNumber
    }

    static func words(in text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).flatMap { chunk -> [String] in
            if isOpaque(String(chunk)) { return [String(chunk)] }
            return chunk.split { !isWordCharacter($0) }
                .filter { $0.contains(where: { $0.isLetter || $0.isNumber }) }
                .map { String($0).trimmingCharacters(in: .punctuationCharacters) }
                .filter { !$0.isEmpty }
        }
    }

    static func sentenceWords(in text: String, limit: Int) -> [String] {
        guard limit > 0 else { return [] }
        let lineStart =
            text.lastIndex(where: \.isNewline)
            .map { text.index(after: $0) } ?? text.startIndex
        var result: [String] = []
        for chunk in text[lineStart...].split(whereSeparator: \.isWhitespace) {
            if isOpaque(String(chunk)) {
                result.append(String(chunk))
                continue
            }
            var word = ""
            for character in chunk {
                if isWordCharacter(character) {
                    word.append(character)
                } else {
                    if !word.isEmpty { result.append(word) }
                    word = ""
                    if ".!?…؟。！？".contains(character) { result.removeAll() }
                }
            }
            if !word.isEmpty { result.append(word) }
        }
        return Array(
            result.map { $0.trimmingCharacters(in: .punctuationCharacters) }
                .filter { !$0.isEmpty }.suffix(limit))
    }
}
