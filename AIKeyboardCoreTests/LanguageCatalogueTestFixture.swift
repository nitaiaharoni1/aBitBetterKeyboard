import UIKit
import XCTest

@testable import AIKeyboardCore

/// Shared helpers for all `LanguageCatalogue*Tests` classes.
///
/// Each test class inherits rather than copies, so the helpers stay in one
/// place and every subclass calls them as `allKeys(language, plane)` etc.
class LanguageCatalogueTestFixture: XCTestCase {

    /// The fourteen that shipped before the catalogue was extended, which is the
    /// set the rules above grandfather.
    static let original: Set<KeyboardLanguage> = [
        .english, .hebrew, .arabic, .french, .german, .greek, .hindi, .italian, .persian,
        .portuguese, .russian, .spanish, .turkish, .ukrainian
    ]

    func locale(for language: KeyboardLanguage) -> Locale {
        Locale(identifier: language.languageTag)
    }

    /// Apple's own word for the space bar in this language, or nil when Apple
    /// ships no localisation for it.
    static func appleSpaceCaption(
        for language: KeyboardLanguage, in bundle: Bundle
    ) -> String? {
        let candidates = [
            language.languageTag, language.languageTag.replacingOccurrences(of: "-", with: "_"),
            String(language.languageTag.prefix(while: { $0 != "-" })),
            language.languageTag == "nb" ? "no" : language.languageTag
        ]
        for candidate in candidates {
            guard let path = bundle.path(forResource: candidate, ofType: "lproj"),
                let localised = Bundle(path: path)
            else { continue }
            let caption = localised.localizedString(
                forKey: "Space", value: Self.missingCaption, table: nil)
            if caption != Self.missingCaption { return caption }
        }
        return nil
    }

    /// **`value:` has to be something no caption could be, and `""` is not it.**
    static let missingCaption = "\u{0}no caption in this lproj\u{0}"

    /// The characters CLDR lists in a language's alphabet that no keyboard here
    /// reaches — every one of them also absent from the three letter rows of
    /// Apple's own macOS layout for the same language.
    static func unreachable(for language: KeyboardLanguage) -> Set<String> {
        switch language {
        case .hindi, .marathi, .nepali: return ["ऌ", "ऽ", "ऍ", "ॅ", "ॐ"]
        default: return []
        }
    }

    /// The language's own alphabet as Apple spells it, folded to the case a key
    /// cap carries and reduced to what a three-row keyboard is answerable for.
    func alphabet(of language: KeyboardLanguage) -> [String] {
        let loc = locale(for: language)
        guard
            let exemplar = (loc as NSLocale).object(forKey: .exemplarCharacterSet)
                as? CharacterSet
        else { return [] }

        let writesWithMarks = KeyboardLayout.rows(for: language, plane: .letters)
            .flatMap(\.keys)
            .contains { key in
                guard case .character(let value) = key.cap,
                    let scalar = value.unicodeScalars.first
                else { return false }
                return scalar.properties.generalCategory == .nonspacingMark
            }

        var found: Set<String> = []
        for value in UInt32(0x20)...UInt32(0x2FFF) {
            guard let scalar = Unicode.Scalar(value), exemplar.contains(scalar) else { continue }
            let category = scalar.properties.generalCategory
            switch category {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter,
                .otherLetter, .spacingMark:
                break
            case .nonspacingMark where writesWithMarks:
                break
            default:
                continue
            }
            let lowered = String(scalar).lowercased(with: loc)
            guard lowered.unicodeScalars.count == 1 else { continue }
            found.insert(lowered)
        }
        return found.sorted()
    }

    func allRows(_ language: KeyboardLanguage, _ plane: KeyboardPlane) -> [KeyRow] {
        KeyboardLayout.rows(for: language, plane: plane)
            + [KeyboardLayout.bottomRow(for: language, plane: plane, showsGlobe: true)]
    }

    func allKeys(_ language: KeyboardLanguage, _ plane: KeyboardPlane) -> [KeySpec] {
        allRows(language, plane).flatMap(\.keys)
    }

    func bottomKeys(_ language: KeyboardLanguage, _ plane: KeyboardPlane) -> [KeySpec] {
        KeyboardLayout.bottomRow(for: language, plane: plane, showsGlobe: true).keys
    }

    /// Everything the letters plane can produce: the keys themselves and their long presses.
    func reachableLetters(_ language: KeyboardLanguage) -> Set<String> {
        reachable(language, .letters)
    }

    /// The same for the two planes that carry punctuation.
    func reachablePunctuation(_ language: KeyboardLanguage) -> Set<String> {
        reachable(language, .numbers).union(reachable(language, .symbols))
    }

    func reachable(_ language: KeyboardLanguage, _ plane: KeyboardPlane) -> Set<String> {
        var out: Set<String> = []
        for key in KeyboardLayout.rows(for: language, plane: plane).flatMap(\.keys) {
            if case .character(let value) = key.cap { out.insert(value) }
            out.formUnion(key.alternates)
        }
        return out
    }
}
