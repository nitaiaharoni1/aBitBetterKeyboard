import Foundation

extension EditScope {

    // MARK: Tokens

    /// A word and the whitespace that followed it, so a message with newlines in
    /// it comes back with the same newlines.
    struct Token {
        let text: String
        let spacing: String
    }

    static func split(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var index = text.startIndex
        while index < text.endIndex {
            while index < text.endIndex, text[index].isWhitespace { index = text.index(after: index) }
            guard index < text.endIndex else { break }
            let word = index
            while index < text.endIndex, !text[index].isWhitespace { index = text.index(after: index) }
            let gap = index
            while index < text.endIndex, text[index].isWhitespace { index = text.index(after: index) }
            tokens.append(Token(text: String(text[word..<gap]), spacing: String(text[gap..<index])))
        }
        return tokens
    }

    /// A token restored from the source may carry the spacing it had at the end
    /// of the message, so an empty gap in the middle becomes a single space.
    static func joined(_ tokens: [Token]) -> String {
        guard let last = tokens.last else { return "" }
        let body = tokens.dropLast().map { $0.text + ($0.spacing.isEmpty ? " " : $0.spacing) }.joined()
        return body + last.text
    }

    // MARK: Alignment

    enum Segment {
        /// Indices into the candidate.
        case unchanged(Range<Int>)
        case changed(source: Range<Int>, candidate: Range<Int>)
    }

    /// Lines the two word lists up on their longest common subsequence and
    /// reports what sits between the matches. Quadratic, over the words of one
    /// chat message.
    static func segments(from source: [String], to candidate: [String]) -> [Segment] {
        var lengths = [[Int]](
            repeating: [Int](repeating: 0, count: candidate.count + 1), count: source.count + 1)
        for i in stride(from: source.count - 1, through: 0, by: -1) {
            for j in stride(from: candidate.count - 1, through: 0, by: -1) {
                lengths[i][j] =
                    source[i] == candidate[j]
                    ? lengths[i + 1][j + 1] + 1
                    : max(lengths[i + 1][j], lengths[i][j + 1])
            }
        }

        var segments: [Segment] = []
        var i = 0, j = 0
        var pendingSource = 0, pendingCandidate = 0
        while i < source.count, j < candidate.count {
            if source[i] == candidate[j] {
                if i > pendingSource || j > pendingCandidate {
                    segments.append(.changed(source: pendingSource..<i, candidate: pendingCandidate..<j))
                }
                segments.append(.unchanged(j..<(j + 1)))
                i += 1
                j += 1
                pendingSource = i
                pendingCandidate = j
            } else if lengths[i + 1][j] >= lengths[i][j + 1] {
                i += 1
            } else {
                j += 1
            }
        }
        if pendingSource < source.count || pendingCandidate < candidate.count {
            segments.append(
                .changed(source: pendingSource..<source.count, candidate: pendingCandidate..<candidate.count))
        }
        return segments
    }
}
