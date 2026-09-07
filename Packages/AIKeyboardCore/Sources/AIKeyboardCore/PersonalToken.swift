import Foundation

enum PersonalToken {
    enum Kind: String, Codable {
        case phone
        case email
    }

    private static func isEmailCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || "@._%+-".contains(character)
    }

    static func kind(of text: String) -> Kind? {
        if isEmail(text) { return .email }
        if PhoneNumberToken.isComplete(text) { return .phone }
        return nil
    }

    static func isEmail(_ text: String) -> Bool {
        guard text.count <= 320 else { return false }
        let halves = text.split(separator: "@", omittingEmptySubsequences: false)
        guard halves.count == 2, !halves[0].isEmpty,
            halves[0].allSatisfy({ isEmailCharacter($0) && $0 != "@" })
        else { return false }
        let labels = halves[1].split(separator: ".", omittingEmptySubsequences: false)
        return labels.count >= 2
            && labels.allSatisfy { label in
                !label.isEmpty && label.first != "-" && label.last != "-"
                    && label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
            }
            && (labels.last.map { $0.count >= 2 && $0.allSatisfy(\.isLetter) } ?? false)
    }

    static func key(for text: String, kind: Kind) -> String? {
        switch kind {
        case .phone:
            return PhoneNumberToken.normalizedPrefix(text)
        case .email:
            guard !text.isEmpty, text.count <= 320, text.allSatisfy(isEmailCharacter) else { return nil }
            return text.precomposedStringWithCanonicalMapping.lowercased()
        }
    }

    static func prefix(in context: String, kind: Kind) -> String? {
        switch kind {
        case .phone:
            return PhoneNumberToken.suffix(in: context)
        case .email:
            let chunk = context.suffix(321).split(whereSeparator: \.isWhitespace).last ?? ""
            guard !chunk.contains("/"), !chunk.contains("\\") else { return nil }
            let suffix = String(context.suffix(321).reversed().prefix(while: isEmailCharacter).reversed())
            guard key(for: suffix, kind: kind) != nil else { return nil }
            return suffix
        }
    }

    static func completionKey(for text: String, kind: Kind) -> String? {
        guard let key = key(for: text, kind: kind),
            (kind == .phone ? key.filter(\.isNumber).count : key.count) >= 3
        else { return nil }
        return key
    }

    static func continues(in context: String, kind: Kind) -> Bool {
        switch kind {
        case .phone:
            return PhoneNumberToken.continues(in: context) || WordBoundary.continuesAfterCursor(in: context)
        case .email:
            guard let first = context.first else { return false }
            return isEmailCharacter(first)
        }
    }

    static func completedText(_ text: String, kind: Kind) -> String {
        guard kind == .email else { return text }
        return String(text.reversed().drop(while: { $0 == "." }).reversed())
    }

    static func accepts(_ input: String, kind: Kind) -> Bool {
        guard !input.isEmpty else { return false }
        switch kind {
        case .phone: return input.allSatisfy(PhoneNumberToken.isCharacter)
        case .email: return input.allSatisfy(isEmailCharacter)
        }
    }
}
