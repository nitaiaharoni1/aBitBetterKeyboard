import Foundation

/// How much of the user's message a Fix is allowed to touch.
///
/// `OutputGuard` answers a different question — whether a *generated* message
/// added a fact nobody said. Fix generates nothing. It is handed a sentence the
/// user wrote and returns the same sentence, so the user's own words are the
/// baseline and every word that comes back different is a claim that the word
/// was wrong. Measured against `Bar/ai-text`, the model makes that claim far too
/// often: it respelled `והכל` as `והכול` — both are correct Hebrew — expanded
/// `dont` to `do not`, put `omg` in capitals, and added full stops to messages
/// with nothing wrong in them. None of that is an error. All of it is the
/// behaviour that makes people turn autocorrect off.
///
/// There are two strengths of it, because the two engines can carry different
/// amounts of instruction.
///
/// `applied(_:to:corrections:)` is the strong one. The cloud model is made to
/// name every mistake before it writes the corrected message, and what it wrote
/// is then reconciled against what it named: a change it did not name is undone,
/// and a message it found nothing wrong with comes back exactly as the user typed
/// it. `repaired(_:to:)` is what is left of that when there is no list — the two
/// corrections below that need no list at all.
///
/// The split is measured, not defensive. Asked for the list as well as the text,
/// Apple's on-device model got materially worse at the text: over the ten English
/// Fix entries in `Bar/ai-text` it started dropping words ("can you send me the
/// id" came back as "you send me the id"), and the extra field cost more than the
/// scope check bought. The cloud model took the same schema and improved. So the
/// list is asked for where it is answered well, and the on-device path gets the
/// half that does not depend on it.
///
/// Two things are deliberately *not* treated as changes, because the reference
/// answers in `Bar/ai-text/reference.json` make both without ever calling them
/// out: punctuation (`מה קורה` → `מה קורה?`, `ticket` → `ticket?`) and
/// capitalisation (`can` → `Can`, `id` → `ID`). Words are compared on their
/// letters alone, so those pass through untouched. Everything else is a word
/// change and has to be accounted for.
///
/// The two list-free corrections were checked against all 24 Fix references with
/// no false positives — see `EditScopeTests`.
public enum EditScope {

    // MARK: Reconciliation

    /// `candidate` with every change the model made on its own initiative undone.
    ///
    /// `corrections` is the list the model wrote before the message, in the shape
    /// `wrong -> right, wrong -> right`. It is read only for the words it names;
    /// the arrows and the ordering are not parsed, because a list that has to be
    /// parsed is a list that fails on the first model that formats it differently.
    public static func applied(
        _ candidate: String,
        to source: String,
        corrections: String
    ) -> String {
        // Nothing wrong means nothing to change — including no full stop on the
        // end. This alone is what keeps an already-correct message intact.
        //
        // **Except a run of letters that is several words with the spaces
        // missing.** That is the WhatsApp case Fix was a no-op on: the model
        // wrote `none` because the corrections field never called missing spaces
        // a mistake, then this returned the jammed string and `applyDirectly`
        // stayed quiet. Spacing is not tidying — the letters did not change —
        // so a split that only inserts whitespace is kept even on `none`.
        guard !declaresNothing(corrections) else {
            return splitsOnlyByWhitespace(candidate, of: source) ? candidate : source
        }
        let named = Set(split(corrections).map { word($0.text) }.filter { !$0.isEmpty })
        return reconciled(candidate, to: source, named: named)
    }

    /// `candidate` with only the changes no model gets right undone: an expanded
    /// contraction and a Hebrew word respelled into its other accepted spelling.
    ///
    /// For the engine that was not asked for a list. Everything else it changed
    /// is taken on trust, because there is nothing here to check it against.
    public static func repaired(_ candidate: String, to source: String) -> String {
        reconciled(candidate, to: source, named: nil)
    }

    /// `named` nil means no list was asked for, so nothing is undone merely for
    /// going unmentioned.
    private static func reconciled(_ candidate: String, to source: String, named: Set<String>?) -> String {
        let original = split(source)
        let corrected = split(candidate)
        guard !original.isEmpty, !corrected.isEmpty else { return source }
        var kept: [Token] = []

        for segment in segments(from: original.map { word($0.text) }, to: corrected.map { word($0.text) }) {
            switch segment {
            case .unchanged(let range):
                kept += corrected[range]

            case .changed(let sourceRange, let candidateRange):
                let was = Array(original[sourceRange])
                let now = Array(corrected[candidateRange])

                if let contraction = restoredContraction(from: was, to: now) {
                    kept.append(contraction)
                    continue
                }
                // Several words jammed into one token, then split. The letters
                // did not change, so this is not a word the model swapped on
                // its own — and the list often describes it as "missing spaces"
                // rather than naming the jammed token, which is the check below
                // that would otherwise put the jammed token back.
                if now.count > was.count, letters(in: was) == letters(in: now),
                    !letters(in: was).isEmpty
                {
                    kept += now
                    continue
                }
                // A word-for-word swap is judged one word at a time, so a
                // sentence where the model corrected one word and quietly
                // improved the one next to it keeps the correction and loses the
                // improvement.
                if was.count == now.count {
                    kept += zip(was, now).map { old, new in
                        if let named, !named.contains(word(old.text)), !named.contains(word(new.text)) {
                            return old
                        }
                        return isSpellingVariant(word(old.text), word(new.text)) ? old : new
                    }
                    continue
                }
                // A span that changed shape cannot be split that way, so all of
                // it has to have been named. An insertion has no source words to
                // look up, so the words it introduced are what is checked.
                guard let named else {
                    kept += now
                    continue
                }
                let claimed = was.isEmpty ? now : was
                kept += claimed.allSatisfy({ named.contains(word($0.text)) }) ? now : was
            }
        }
        return withoutAnAddedHebrewFullStop(joined(kept), source: source)
    }

    /// Whether `candidate` is a leftover scrap of `source` rather than a
    /// correction of it.
    ///
    /// Fix used to replace the whole field with whatever the model wrote. When
    /// that was only the last sentence, the rest of the message disappeared.
    /// Short messages are left alone: two or three words can legitimately shrink
    /// (`thx` → `thanks` is not a fragment).
    public static func isFragment(_ candidate: String, of source: String) -> Bool {
        let original = split(source)
        let corrected = split(candidate)
        guard original.count >= 6, !corrected.isEmpty else { return false }
        return corrected.count * 2 < original.count
    }

    /// Whether the model reported no mistakes. The field is required, so a model
    /// with nothing to report writes a placeholder rather than leaving it blank.
    public static func declaresNothing(_ corrections: String) -> Bool {
        let text = corrections.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return text.isEmpty
            || ["none", "n/a", "na", "null", "-", "nothing", "no errors", "אין", "אין שגיאות", "ללא"]
                .contains(text)
    }

    /// `candidate` is `source` with spaces inserted between letters and nothing
    /// else changed — not a full stop, not a question mark, not a respelling.
    ///
    /// Joining words back together is refused: that is the model deleting the
    /// spaces the writer typed, which is the opposite of this recovery.
    public static func splitsOnlyByWhitespace(_ candidate: String, of source: String) -> Bool {
        candidate.filter { !$0.isWhitespace } == source.filter { !$0.isWhitespace }
            && split(candidate).count > split(source).count
    }

    /// The same words in the same order, ignoring punctuation, capitalisation
    /// and spacing.
    ///
    /// **Punctuate and Polish ask for marks the model will not name as a word
    /// mistake**, so `applied` on `none` would throw the period away. Those
    /// styles keep the candidate when this is true; a candidate that also
    /// changed a word fails it and falls through to the ordinary scope check.
    public static func sameWords(_ candidate: String, as source: String) -> Bool {
        split(candidate).map { word($0.text) } == split(source).map { word($0.text) }
    }

    // MARK: The two corrections made without asking

    /// A contraction the writer typed without its apostrophe, when the model
    /// expanded it instead of repairing it.
    ///
    /// `dont` is a typo for `don't`, not shorthand for `do not`: expanding it
    /// changes the writer's register on a message they only wanted spellchecked.
    /// The reverse — leaving `dont` alone — is not the answer either, so this
    /// puts back the contraction rather than the original.
    ///
    /// Keyed by the apostrophe-less spelling, which is the only form a writer
    /// produces by accident. `ill` and `lets` are deliberately absent: both are
    /// ordinary words, and a rule that rewrites "I was ill last week" is worse
    /// than the one it fixes.
    private static let contractions: [String: (expansion: [String], corrected: String)] = [
        "dont": (["do", "not"], "don't"),
        "wont": (["will", "not"], "won't"),
        "cant": (["can", "not"], "can't"),
        "isnt": (["is", "not"], "isn't"),
        "doesnt": (["does", "not"], "doesn't"),
        "didnt": (["did", "not"], "didn't"),
        "wasnt": (["was", "not"], "wasn't"),
        "werent": (["were", "not"], "weren't"),
        "hasnt": (["has", "not"], "hasn't"),
        "havent": (["have", "not"], "haven't"),
        "wouldnt": (["would", "not"], "wouldn't"),
        "couldnt": (["could", "not"], "couldn't"),
        "shouldnt": (["should", "not"], "shouldn't"),
        "im": (["i", "am"], "I'm"),
        "ive": (["i", "have"], "I've"),
        "youre": (["you", "are"], "you're"),
        "theyre": (["they", "are"], "they're"),
        "thats": (["that", "is"], "that's"),
        "whats": (["what", "is"], "what's")
    ]

    private static func restoredContraction(from was: [Token], to now: [Token]) -> Token? {
        guard was.count == 1, now.count == 2,
            let contraction = contractions[word(was[0].text)],
            now.map({ word($0.text) }) == contraction.expansion
        else { return nil }
        let repaired = capitalised(contraction.corrected, like: was[0].text)
        return Token(
            text: leadingPunctuation(was[0].text) + repaired + trailingPunctuation(now[1].text),
            spacing: now[1].spacing
        )
    }

    /// A message in Hebrew does not take a full stop on the end the way an
    /// English one does, and the corpus is unambiguous about it: every one of the
    /// five references that adds a terminal full stop is English-only, and not one
    /// of the sixteen Hebrew or code-switched references adds one. `fix-he-04` is
    /// tagged `punctuation-register` and lists "add a full stop" as a thing the
    /// answer must not do.
    ///
    /// So a full stop on the end of a Hebrew message is the model tidying rather
    /// than correcting. Only an added one is refused — a full stop the writer
    /// typed themselves always stays.
    private static func withoutAnAddedHebrewFullStop(_ result: String, source: String) -> String {
        guard LanguageDetector.scripts(in: source).contains(.hebrew),
            result.hasSuffix("."), !result.hasSuffix(".."), !source.hasSuffix(".")
        else { return result }
        return String(result.dropLast())
    }

    /// Hebrew is written in two accepted orthographies, and `הכל` and `הכול` are
    /// the same word in both of them. Swapping one for the other is a house-style
    /// preference, not a correction, and on a keyboard it reads as the machine
    /// disagreeing with how the user spells.
    ///
    /// The test is deliberately one-directional: the shorter spelling has to be
    /// the longer one with only ו and י taken out. That is what separates it from
    /// a real correction — `תגדי` → `תגיד` moves a י rather than adding one, and
    /// `יבדוק` → `אבדוק` replaces one letter with another, so neither matches.
    private static let matresLectionis: Set<Character> = ["ו", "י"]

    private static func isSpellingVariant(_ a: String, _ b: String) -> Bool {
        guard a != b, !a.isEmpty, !b.isEmpty, LanguageDetector.scripts(in: a).contains(.hebrew)
        else { return false }
        let shorter = Array(a.count < b.count ? a : b)
        let longer = a.count < b.count ? b : a
        guard shorter.count < longer.count else { return false }

        var matched = 0
        for character in longer {
            if matched < shorter.count, character == shorter[matched] {
                matched += 1
            } else if !matresLectionis.contains(character) {
                return false
            }
        }
        return matched == shorter.count
    }

    // MARK: Words

    /// A token reduced to the letters and digits that make up its word, so that
    /// punctuation and capitalisation never register as a change.
    private static func word(_ token: String) -> String {
        token.filter { $0.isLetter || $0.isNumber }.lowercased()
    }

    private static func letters(in tokens: [Token]) -> String {
        tokens.map { word($0.text) }.joined()
    }

    private static func leadingPunctuation(_ token: String) -> String {
        String(token.prefix { !$0.isLetter && !$0.isNumber })
    }

    private static func trailingPunctuation(_ token: String) -> String {
        String(token.suffix(while: { !$0.isLetter && !$0.isNumber }))
    }

    private static func capitalised(_ replacement: String, like original: String) -> String {
        guard let first = original.first(where: { $0.isLetter }), first.isUppercase,
            let head = replacement.first
        else { return replacement }
        return head.uppercased() + replacement.dropFirst()
    }

}

extension StringProtocol {
    /// The trailing run of characters satisfying `predicate`, in order.
    fileprivate func suffix(while predicate: (Character) -> Bool) -> String {
        String(reversed().prefix(while: predicate).reversed())
    }
}
