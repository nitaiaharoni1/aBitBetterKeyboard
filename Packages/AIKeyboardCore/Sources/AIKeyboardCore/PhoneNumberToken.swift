import Foundation

enum PhoneNumberToken {
    private static let separators: Set<Character> = [" ", "\u{00A0}", "\u{202F}", "-", "(", ")"]

    static func isCharacter(_ character: Character) -> Bool {
        character.isNumber || character == "+" || separators.contains(character)
    }

    static func continues(in text: String) -> Bool {
        for character in text.prefix(40) {
            if character.isNumber || character == "+" { return true }
            if !separators.contains(character) { return false }
        }
        return false
    }

    static func normalizedPrefix(_ text: String) -> String? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 40 else { return nil }
        var normalized = ""
        for (index, character) in text.enumerated() {
            if let digit = character.wholeNumberValue, (0...9).contains(digit), character.isNumber {
                normalized += String(digit)
            } else if character == "+", index == 0 {
                normalized += "+"
            } else if !separators.contains(character) {
                return nil
            }
        }
        guard normalized.contains(where: \.isNumber) else { return nil }
        return normalized
    }

    static func isComplete(_ text: String) -> Bool {
        guard let normalized = normalizedPrefix(text) else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hasValidBounds(trimmed), hasBalancedParentheses(trimmed) else { return false }
        let digits = normalized.compactMap(\.wholeNumberValue)
        return hasValidDigits(digits, international: normalized.hasPrefix("+"))
            && Set(digits).count > 2
            && !failsLongNumberChecksum(digits)
    }

    private static func hasValidBounds(_ text: String) -> Bool {
        (text.first?.isNumber == true || text.first == "+" || text.first == "(")
            && (text.last?.isNumber == true || text.last == ")")
    }

    private static func hasValidDigits(_ digits: [Int], international: Bool) -> Bool {
        if international { return (8...15).contains(digits.count) && digits.first != 0 }
        return (9...11).contains(digits.count) && (digits.count != 9 || digits.first == 0)
    }

    private static func hasBalancedParentheses(_ text: String) -> Bool {
        var parentheses = 0
        for character in text {
            if character == "(" { parentheses += 1 }
            if character == ")" { parentheses -= 1 }
            if parentheses < 0 || parentheses > 1 { return false }
        }
        return parentheses == 0
    }

    private static func failsLongNumberChecksum(_ digits: [Int]) -> Bool {
        guard digits.count >= 13 else { return false }
        let checksum = digits.reversed().enumerated().reduce(0) { sum, item in
            let digit = item.offset.isMultiple(of: 2) ? item.element : item.element * 2
            return sum + (digit > 9 ? digit - 9 : digit)
        }
        return checksum.isMultiple(of: 10)
    }

    static func suffix(in context: String) -> String? {
        let suffix = context.suffix(64).reversed().prefix {
            isCharacter($0)
        }.reversed()
        let raw = String(suffix)
        if raw.first?.isWhitespace != true, raw.first != "(",
            let previous = context.dropLast(raw.count).last,
            previous.isLetter || previous.isNumber || previous == "_" || previous == "@" || previous == "."
        {
            return nil
        }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedPrefix(text) != nil else { return nil }
        return text
    }
}
