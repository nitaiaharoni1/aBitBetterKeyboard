import Foundation

public enum DictationTextNormalizer {
    private static let fragments = try! NSRegularExpression(
        pattern:
            #"(?=((?<![\p{L}\p{M}])(?=[\p{L}\p{M}]+(?:\h+['׳’ʼ"״“”]|['׳’ʼ"״“”]\h+))([\p{L}\p{M}]+)(\h*)(['׳’ʼ"״“”])(\h*)([\p{L}\p{M}]+)(?![\p{L}\p{M}])))"#
    )
    private static let quotation = try! NSRegularExpression(
        pattern:
            #"(?<![\p{L}\p{M}])(?:'[^'\r\n]+?(?<!\s)'|‘[^‘’\r\n]+?(?<!\s)’|"[^"\r\n]+?(?<!\s)"|“[^“”\r\n]+?(?<!\s)”)(?![\p{L}\p{M}])"#
    )

    public static func normalize(_ text: String) -> String {
        var result = text
        while true {
            let range = NSRange(result.startIndex..., in: result)
            let quoteDelimiters = quotation.matches(in: result, range: range).flatMap {
                [
                    NSRange(location: $0.range.location, length: 1),
                    NSRange(location: NSMaxRange($0.range) - 1, length: 1)
                ]
            }
            let matches = fragments.matches(in: result, range: range)
            var changed = false
            for match in matches.reversed() {
                let markRange = match.range(at: 4)
                guard !quoteDelimiters.contains(where: { NSIntersectionRange($0, markRange).length > 0 }),
                    let leftRange = Range(match.range(at: 2), in: result),
                    let rightRange = Range(match.range(at: 6), in: result),
                    let symbolRange = Range(markRange, in: result),
                    let wholeRange = Range(match.range(at: 1), in: result)
                else { continue }
                let before = match.range(at: 3).length
                let after = match.range(at: 5).length
                guard before + after > 0 else { continue }
                let left = String(result[leftRange])
                let right = String(result[rightRange])
                let symbol = String(result[symbolRange])
                guard shouldJoin(left: left, right: right, symbol: symbol, before: before, after: after)
                else { continue }
                result.replaceSubrange(wholeRange, with: left + symbol + right)
                changed = true
            }
            if !changed { return result }
        }
    }

    private static func shouldJoin(
        left: String, right: String, symbol: String, before: Int, after: Int
    ) -> Bool {
        let letters = CharacterSet.letters.subtracting(.nonBaseCharacters)
        let leftLetters = left.unicodeScalars.filter { letters.contains($0) }
        let rightLetters = right.unicodeScalars.filter { letters.contains($0) }
        guard !leftLetters.isEmpty, !rightLetters.isEmpty else { return false }
        let allLetters = leftLetters + rightLetters
        if allLetters.allSatisfy({ (0x05D0...0x05EA).contains($0.value) }) {
            return shouldJoinHebrew(
                left: left, right: right, symbol: symbol, before: before, after: after)
        }
        guard ["'", "’", "ʼ"].contains(symbol),
            allLetters.allSatisfy({ (65...90).contains($0.value) || (97...122).contains($0.value) })
        else { return false }
        return shouldJoinEnglish(left: left, right: right)
    }

    private static func shouldJoinHebrew(
        left: String, right: String, symbol: String, before: Int, after: Int
    ) -> Bool {
        let leftLetters = left.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        let rightLetters = right.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        if ["\"", "״", "“", "”"].contains(symbol) { return rightLetters.count == 1 }
        guard let last = leftLetters.last, "גזצ".unicodeScalars.contains(last) else { return false }
        return leftLetters.count > 1 || before > 0 || after == 0 || rightLetters.count == 1
    }

    private static func shouldJoinEnglish(left: String, right: String) -> Bool {
        let stem = left.lowercased()
        switch right.lowercased() {
        case "t":
            return [
                "ain", "aren", "can", "couldn", "daren", "didn", "doesn", "don", "hadn", "hasn",
                "haven", "isn", "mayn", "mightn", "mustn", "needn", "oughtn", "shan", "shouldn",
                "wasn", "weren", "won", "wouldn"
            ].contains(stem)
        case "m": return stem == "i"
        case "re": return ["you", "we", "they", "who", "what", "where", "there"].contains(stem)
        case "ve":
            return ["i", "you", "we", "they", "who", "could", "should", "would", "might", "must"].contains(
                stem)
        case "s", "d", "ll": return true
        default: return false
        }
    }
}
