import Foundation
import UIKit

extension GroupedKeys {

    /// Whether this *field* may be grouped, on top of the language question.
    ///
    /// **A decoder cannot help with a string that is not a word, and will wreck
    /// it.** A password, an email address, a URL and a username are typed exactly
    /// or not at all, so grouping them offers nothing and costs everything — and
    /// in a password field the user cannot even see what went wrong.
    ///
    /// Composed with `SecureField.permitsRead` rather than restating it, so "is
    /// this a credential" has one spelling. The extra list is separate on purpose:
    /// `SecureField.sensitive` is deliberately short because each entry there
    /// costs a screen the user asked to have read, which is a different trade
    /// from this one — refusing to group an email field costs nothing.
    ///
    /// **It lives here rather than in `GroupedKeys.swift` because that file is
    /// Foundation-only and has to stay that way.** `UITextContentType` is UIKit,
    /// and `Bar/grouped/harness/swift-check.sh` compiles the grouping against the
    /// *host* to check it against the Python that measured it — which it can only
    /// do while there is no platform framework in there. The import broke that
    /// check the moment it was added, which is the check earning its keep.
    public static func permitted(secure: Bool?, contentType: UITextContentType??) -> Bool {
        guard SecureField.permitsRead(secure: secure, contentType: contentType) else {
            return false
        }
        guard let inner = contentType, let type = inner else { return true }
        return !typedExactly.contains(type)
    }

    /// Fields whose content is not language, so no language model can improve it.
    public static let typedExactly: Set<UITextContentType> = [
        .emailAddress, .URL, .username, .telephoneNumber, .creditCardNumber
    ]
}

/// The word being typed on grouped keys, before anybody knows what it is.
///
/// **Grouped keys break the oldest rule the suggestion bar has** — that slot zero
/// holds exactly the characters that were keyed — because there are no such
/// characters: a press on `[qwer]` is four possibilities, not a letter. The rule
/// is replaced rather than dropped, and the replacement is that **there is always
/// a route to the exact letter the user meant**: long-press the key, pick the
/// letter, and that position is pinned for the rest of the word. A tap that
/// lands clearly on one letter of the group is the same pin without the popup.
public final class GroupedInput {

    /// One key press: the cap that was hit, and the letter the user pinned by
    /// long-pressing it, if they did.
    struct Stroke {
        let cap: String
        var pinned: String?
    }

    private(set) var strokes: [Stroke] = []
    private var decoder: GroupedDecoder?
    private var capCache: (language: KeyboardLanguage, level: GroupedKeys.Level, caps: Set<String>)?

    /// Whether shift was down when the word started. Read once rather than per
    /// keystroke, because a one-shot shift is consumed by the first press and
    /// every later keystroke would then decide the word was lower case.
    var startedShifted = false

    /// The exact text last written into the field for this word, so the next
    /// press can tell whether it is still there. Empty when no word is open.
    var lastWritten = ""

    var isTyping: Bool { !strokes.isEmpty }

    /// A candidate wearing the case the word was started in.
    ///
    /// Only the first character, because that is what shift means for a word:
    /// `⇧` then `t`, `h`, `e` is `The`, never `THE`. Caps Lock is a different
    /// state and `KeyCap.shift` already tells them apart.
    func cased(_ word: String, in language: KeyboardLanguage) -> String {
        guard startedShifted, let first = word.first else { return word }
        return language.uppercased(String(first)) + word.dropFirst()
    }

    // MARK: The decoder, cached

    /// Rebuilt only when the language or the level changes — indexing tens of
    /// thousands of words is milliseconds, and doing it per keystroke would be
    /// milliseconds per keystroke against a 20 ms budget for the whole keyboard.
    func decoder(
        language: KeyboardLanguage, level: GroupedKeys.Level, personal: [String]
    )
        -> GroupedDecoder
    {
        if let cached = decoder, cached.language == language, cached.level == level {
            return cached
        }
        let built = GroupedDecoder(language: language, level: level, personal: personal)
        decoder = built
        return built
    }

    /// The caps this keyboard draws as grouped letter keys, at this language and
    /// level.
    ///
    /// **Cached beside the decoder and for the same reason**: it is asked at every
    /// keystroke, and answering it means planning the whole layout.
    func caps(language: KeyboardLanguage, level: GroupedKeys.Level) -> Set<String> {
        if let cached = capCache, cached.language == language, cached.level == level {
            return cached.caps
        }
        let base = KeyboardLayout.letterLayouts[language]
        let built = Set(
            base.map { GroupedKeys.layout($0, language: language, level: level).rows.flatMap { $0 } }
                ?? [])
        capCache = (language, level, built)
        return built
    }

    /// Whether this key press means the word the strokes describe is over.
    ///
    /// **Everything except another letter, a delete and a shift ends it.** The
    /// strokes describe the word *behind the cursor*, so the moment anything
    /// moves the cursor, opens a plane, switches language or writes text this
    /// keyboard did not decode, they describe a word that is no longer there —
    /// and the next press would rewrite whatever now sits under it. Shift is the
    /// exception because it changes the next letter without ending the word.
    ///
    /// Written as "which caps continue" rather than "which caps interrupt" on
    /// purpose: a new cap added to `KeyCap` then ends a grouped word by default,
    /// which is the safe way round.
    static func interrupts(_ cap: KeyCap) -> Bool {
        switch cap {
        case .character, .backspace, .shift: return false
        default: return true
        }
    }

    // MARK: Editing the word

    func append(cap: String, pin: String? = nil) {
        let allowed = pin.flatMap { GroupedKeys.letters(inCap: cap).contains($0) ? $0 : nil }
        strokes.append(Stroke(cap: cap, pinned: allowed))
    }

    /// Pin the last stroke to one letter. Called when a long press picks a letter
    /// out of the group that was just pressed.
    ///
    /// Returns false when the letter is not in the last group, which happens when
    /// a long press lands on a key that is *not* the one in progress — that is an
    /// ordinary alternate (an accent), not a pin.
    @discardableResult
    func pinLast(to letter: String) -> Bool {
        guard var last = strokes.last,
            GroupedKeys.letters(inCap: last.cap).contains(letter)
        else { return false }
        last.pinned = letter
        strokes[strokes.count - 1] = last
        return true
    }

    func removeLast() { if !strokes.isEmpty { strokes.removeLast() } }

    func clear() {
        strokes = []
        startedShifted = false
        lastWritten = ""
    }

    // MARK: Reading it back

    /// The keystroke sequence, in the form `GroupedDecoder` indexes by.
    func code(language: KeyboardLanguage, level: GroupedKeys.Level) -> String {
        let map = GroupedDecoder.letterToKey(language: language, level: level)
        var out = String.UnicodeScalarView()
        for stroke in strokes {
            guard let letter = GroupedKeys.letters(inCap: stroke.cap).first,
                let key = map[letter]
            else { continue }
            out.append(UnicodeScalar(UInt32(0xE000 + key))!)
        }
        return String(out)
    }

    /// Positions the user pinned, and to what.
    var pins: [Int: String] {
        var out: [Int: String] = [:]
        for (index, stroke) in strokes.enumerated() where stroke.pinned != nil {
            out[index] = stroke.pinned
        }
        return out
    }

    /// What goes in the field when the decoder has nothing: the pinned letter
    /// where there is one, the first letter of the group otherwise.
    ///
    /// **The field may never go blank while somebody is typing.** A decoder with
    /// no answer still has to show the keystrokes, or a user cannot tell a
    /// keyboard that is guessing badly from one that has stopped responding.
    var literal: String {
        strokes.map { $0.pinned ?? (GroupedKeys.letters(inCap: $0.cap).first ?? "") }.joined()
    }
}

// MARK: - Driving it from the keyboard

extension KeyboardController {

    /// The level in force for the language on screen, or `.off`.
    ///
    /// Read through `SharedStore` at the keystroke rather than from a cached
    /// copy — the same rule `storedAutocorrect` and `storedPersonalDictionary`
    /// follow, and for the same reason: the switch is in the containing app and
    /// every press it governs happens in the extension, so an instance iOS kept
    /// alive would otherwise go on grouping after the user turned it off.
    var groupingLevel: GroupedKeys.Level {
        guard GroupedKeys.supports(language),
            // A password, email or URL field is typed exactly or not at all.
            GroupedKeys.permitted(
                secure: target?.isSecureTextEntry ?? nil, contentType: fieldContentType),
            // **The emoji search box is not the document**, so the decoder — which
            // works by rewriting the word behind the cursor — has nothing it can
            // write into. The keys go back to one letter each while it is open,
            // which is the same trade that box already makes: it exists to put an
            // alphabet back on screen.
            !overlay.isEmoji
        else { return .off }
        return SharedStore.shared.storedGroupedLevel.capped(for: language)
    }

    var isGroupedTyping: Bool { groupingLevel != .off }

    /// Whether this cap is one of the grouped letter keys this keyboard is
    /// currently drawing.
    ///
    /// **Membership, not shape, and the difference is a shipped defect.** This
    /// asked whether the cap carried more than one letter, and `SlotAction.text`
    /// compiles to `.character(".com")` — so with grouping on, the `.com` key in a
    /// customised bottom row was fed to the *decoder* as a keystroke instead of
    /// typing anything, and so were `,` `?` `!` `@` on any layout that had moved
    /// them. The letter count is still asked first because it is the cheap half
    /// and because a one-letter group is an ordinary key.
    func isGroupedCap(_ value: String) -> Bool {
        let level = groupingLevel
        guard level != .off, GroupedKeys.letters(inCap: value).count > 1 else { return false }
        return grouped.caps(language: language, level: level).contains(value)
    }

    /// One grouped key press: record it, decode, and put the best guess in the
    /// field.
    ///
    /// The guess is *written into the document* rather than held to one side,
    /// because a person typing has to see words appear. That is what
    /// `replaceCurrentWord` is already for, and it is why the pending word does
    /// not need its own rendering anywhere.
    func pressGroupedKey(_ cap: String, at unitPoint: CGPoint? = nil) {
        block = nil
        clearRevertibleEdit()

        // **The strokes are a claim about the characters behind the cursor, and
        // the cursor can move without this keyboard hearing about it.** Tapping
        // elsewhere in the host's field goes through no key, so `interrupts`
        // never fires and the strokes survive somewhere they no longer describe —
        // at which point the next press rewrites whatever word is now there. So
        // the claim is checked rather than trusted: if the field no longer holds
        // what was last written into it, the word starts here.
        if grouped.isTyping, currentWordPrefix != grouped.lastWritten {
            grouped.clear()
        }
        // Shift is read once, at the first key. Reading it per keystroke made the
        // capital vanish on the second one: `applyGroupedGuess` consumes a
        // one-shot shift, so `The` decoded as `The`, then `the`.
        if !grouped.isTyping { grouped.startedShifted = shift.isUppercase }

        // A tap clearly on one letter of the group is a soft pin: the same filter
        // a long press applies, without opening the popup. A tap in the middle
        // of the key leaves the decoder to guess. VoiceOver sends no point.
        let pin = unitPoint.flatMap {
            GroupedKeys.letter(atX: Double($0.x), y: Double($0.y), in: GroupedKeys.lines(inCap: cap))
        }
        grouped.append(cap: cap, pin: pin)
        applyGroupedGuess()
    }

    /// Re-decode and rewrite the word in progress.
    func applyGroupedGuess() {
        guard grouped.isTyping else { return }
        let level = groupingLevel
        let decoder = grouped.decoder(
            language: language, level: level, personal: personalWordsForDecoding)
        let code = grouped.code(language: language, level: level)
        let pins = grouped.pins
        let candidates = decoder.candidates(startingWith: code, pinnedTo: pins, limit: 3)
        let guess = grouped.cased(candidates.first ?? grouped.literal, in: language)
        replaceCurrentWord(with: guess)
        grouped.lastWritten = guess
        if shift == .on { shift = .off }
        showGroupedCandidates(candidates.map { grouped.cased($0, in: language) })
    }

    /// The bar, while a grouped word is in progress.
    ///
    /// **Slot zero is the literal reading, not the top candidate**, which is the
    /// nearest thing left to the rule grouped keys broke: whatever the decoder
    /// believes, the keys the user actually pressed are always one tap away. The
    /// bold slot — what the space bar commits — is still the decoder's best
    /// answer, because committing the literal by default would make the feature
    /// pointless.
    private func showGroupedCandidates(_ candidates: [String]) {
        var slots: [Suggestion] = []
        var seen = Set<String>()
        for word in candidates + [grouped.literal] where seen.insert(word).inserted {
            slots.append(Suggestion(text: word, language: language))
            if slots.count == 3 { break }
        }
        // Bold the decoder's answer when it has one; with nothing but the literal
        // there is nothing to bold, because space would only be re-committing what
        // is already in the field.
        suggestions =
            candidates.isEmpty ? slots : SuggestionEngine.markDefault(slots, at: 0)
    }

    /// Backspace takes back a whole key press, not a letter.
    ///
    /// **A letter would be wrong twice over**: the letters in the field were never
    /// typed individually, and deleting one of them leaves a word the remaining
    /// keystrokes cannot produce, so the next press decodes from a code that no
    /// longer matches what is on screen. Returns false when no grouped word is in
    /// progress, so ordinary deletion carries on.
    func deleteGroupedStroke() -> Bool {
        guard grouped.isTyping else { return false }
        grouped.removeLast()
        if grouped.isTyping {
            applyGroupedGuess()
        } else {
            // Deleting the last stroke empties the word, so `clear()` and not
            // just an empty `strokes`: `lastWritten` has to go too, or the next
            // press compares the field against a word that is no longer in it and
            // decides the cursor moved.
            replaceCurrentWord(with: "")
            grouped.clear()
            refreshSuggestions()
        }
        return true
    }

    /// A long press picked one letter out of the group just pressed.
    /// Returns false if it was an ordinary alternate, which the caller then
    /// handles the old way.
    func pinGroupedLetter(_ letter: String) -> Bool {
        guard grouped.isTyping, grouped.pinLast(to: letter) else { return false }
        applyGroupedGuess()
        return true
    }

    /// Anything that ends the word — space, punctuation, return, or the cursor
    /// moving — closes the grouped session, because the strokes no longer
    /// describe the word under the cursor.
    func endGroupedWord() { grouped.clear() }

    /// Words the decoder should rank above the corpus: the user's own dictionary
    /// and what the keyboard has learned. The same precedence
    /// `SuggestionEngine.Source` already encodes.
    private var personalWordsForDecoding: [String] {
        SharedStore.shared.storedPersonalDictionary + personal.allWords(in: language)
    }
}
