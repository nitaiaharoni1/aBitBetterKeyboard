import Foundation

// MARK: - AI actions

public enum AIAction: String, CaseIterable, Identifiable, Hashable, Sendable {
    /// Answers the message the user copied.
    ///
    /// **It used to say "on screen", and that is the capability
    /// `FeatureFlags.screenCaptureReply` holds back.** In v1 the message comes
    /// from the CopyClip ledger rather than from a ReplayKit reading, so this is
    /// the one action whose usefulness depends on something the user did in
    /// *another* app a moment ago. It still leads the menu and still explains
    /// itself when it cannot run; what changed is which sentence it explains.
    /// See `ReplySource` for the order the sources are preferred in.
    case reply
    case fix
    case rewrite
    case tone

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .reply: return "Reply"
        case .fix: return "Fix"
        case .rewrite: return "Rewrite"
        case .tone: return "Tone"
        }
    }

    public var subtitle: String {
        switch self {
        // "Copied" rather than "on screen", because the pasteboard is where v1
        // gets the message.
        //
        // **Nothing reads this property today**, checked across every target on
        // 2026-08-18: the only `.subtitle` call sites belong to `BrandPalette`
        // and `AppSearchItem`. It is corrected rather than deleted because it is
        // public API of a public enum and a wrong string is a trap for the first
        // screen that draws one. If it is still unread the next time somebody
        // passes through here, delete it instead of maintaining it.
        //
        // Kept to the length of the three below it, and naming no key position,
        // for whenever that happens: CopyClip is movable in the layout editor,
        // and Reply's end of the suggestion bar is the leading end, which is the
        // right-hand one in Hebrew.
        case .reply: return "Answer what you copied"
        case .fix: return "Grammar & spelling"
        case .rewrite: return "Three ways to say it"
        case .tone: return "Pick a register"
        }
    }

    public var icon: String {
        switch self {
        case .reply: return "arrowshape.turn.up.left"
        case .fix: return "checkmark.circle"
        case .rewrite: return "arrow.triangle.2.circlepath"
        case .tone: return "slider.horizontal.3"
        }
    }

    /// Whether this action has something to work on when the field is empty.
    ///
    /// **It was `needsScreenContext`, and that name stopped being true.** It never
    /// described what the property decides — `isAvailable` uses it to mean "an
    /// empty field is not a reason to grey this out" — and once v1 sourced Reply
    /// from the pasteboard it named a mechanism the build does not even contain.
    /// Renamed for the reason `AIEdit.replacedSelection` became `AIEdit.undo`: a
    /// name that lies about its callers is worse than a long one.
    ///
    /// Reply is the only action this is true of, and it is true for a reason that
    /// outlives the source: it answers a message somebody *else* wrote, so the
    /// user having typed nothing yet is the ordinary case rather than the
    /// degenerate one. Fix, Rewrite and Tone all act on the user's own words and
    /// genuinely have nothing to do without them.
    public var worksWithoutTypedText: Bool { self == .reply }

    /// Whether this action has anything to do right now.
    ///
    /// Reply stays available without text on purpose — answering a message you have
    /// not started writing is the whole point of it — and the text actions genuinely
    /// have nothing to work on without any.
    ///
    /// **This lived on `AIMenuPanel` and outlived it**, because the panel was never
    /// the reason it existed: `SuggestionBar` reads it to decide whether its own
    /// controls are lit, and the bar and the panel disagreeing about what an empty
    /// field means was D8's defect. The panel is deleted; the question is not.
    public func isAvailable(hasTextToWorkWith: Bool) -> Bool {
        worksWithoutTypedText ? true : hasTextToWorkWith
    }

    /// Whether *any* action could run right now.
    ///
    /// Written as a question over the list rather than as `true` so that a future
    /// action set cannot make it a lie without failing `SparkleReachabilityTests`.
    /// Reply is always available, so today it is always true.
    public static func hasRunnableAction(hasTextToWorkWith: Bool) -> Bool {
        allCases.contains { $0.isAvailable(hasTextToWorkWith: hasTextToWorkWith) }
    }
}

// MARK: - An edit that can be taken back

/// Something this keyboard wrote into the field on the user's behalf, and the
/// text it replaced.
///
/// **Fix and Rewrite apply themselves now, so undo is not a nicety.** They used
/// to put an answer in the banner behind a Use button, which made accepting the
/// change the user's own act; applying it on arrival is faster and reads better —
/// the correction appears in the sentence rather than beside it — but it also
/// means the keyboard has changed somebody's message without being asked twice.
/// `UITextDocumentProxy` has no undo of any kind, so the only way back is to have
/// kept what was there.
///
/// **It was `AIEdit` until CopyClip started pasting whole paragraphs on one
/// tap.** A clip insert is the same event seen from a different key: text the
/// user did not type, arriving in one movement, with no way back once it is in.
/// Its lifetime is identical too, so a second slot beside this one would be a
/// second thing to retire everywhere this one is retired, and the first place
/// anybody forgot would delete characters the user typed. One slot, one step, one
/// implementation of "delete exactly what was put in, from where it was put in".
///
/// **How long it lasts is `rebased(onto:)` and `spanUndo(behind:)`, and it used
/// to be one keystroke.** That was safe and far too short: it expired before the
/// wrong word had been read in the sentence it landed in, which is when anybody
/// notices one (NIT-154). Both functions locate what this edit wrote inside the
/// document and refuse unless they find it exactly once, so an undo taken after
/// half a sentence more has been typed puts back the span and leaves that half
/// sentence alone. `KeyboardController.expireRevertibleEditIfUnusable` asks the
/// same question once per document change, so the control is never drawn over an
/// undo that would do nothing or do harm.
///
/// `applied` is held as well as `previous` because the revert has to find and
/// delete exactly what was inserted, wherever in the field it has since ended
/// up. `documentIdentifier` closes the other ambiguity: identical text in a new
/// host field is still a different document and cannot satisfy this undo.
public struct RevertibleEdit: Equatable, Sendable {
    /// Which key wrote it, and therefore what the undo control calls itself. The
    /// text actions carry their own `AIAction` rather than collapsing into one
    /// case, because the button names the thing it undoes rather than saying
    /// "Undo" — by the time it is read the field has already changed, and the
    /// word is the only thing saying *what* changed it.
    public let origin: Origin
    /// What the span the edit replaced held before it ran. Read at the moment
    /// of the replacement rather than at the moment the call started, so it is
    /// what was *actually* taken out even if the field moved while the model was
    /// thinking.
    public let previous: String
    /// What the edit put there.
    public let applied: String
    /// The host document that received the edit. A matching string in another
    /// field is not the same edit and must never be changed by this undo.
    public let documentIdentifier: UUID?

    /// **How to put it back, and this is not bookkeeping.** The two undo
    /// differently and getting it wrong destroys the user's message: a Fix over
    /// the selected word `wrold` in `hello there wrold friend` replaces five
    /// characters, and a revert that put `previous` back the way a whole-field
    /// edit does would leave the field holding the single word `wrold`. See
    /// `KeyboardController.revertEdit`.
    public let undo: Undo

    /// What made the edit.
    public enum Origin: Equatable, Sendable {
        case ai(AIAction)
        /// A clip inserted from the CopyClip panel.
        case clip
        /// A misplaced word boundary repaired from the suggestion bar.
        case spacing

        /// What the undo control is called out loud. It names the action rather
        /// than saying "Undo", for the reason `SuggestionBar.revertButton` gives:
        /// the field has already changed by the time anybody reads it.
        public var undoLabel: String {
            switch self {
            case .ai(let action): return "Undo \(action.title)"
            case .clip: return "Undo paste"
            case .spacing: return "Undo spacing"
            }
        }
    }

    /// Which shape of edit this was, from the undo's point of view — which is the
    /// only point of view that matters by the time it is read.
    ///
    /// **It was a `replacedSelection` flag until Reply started applying itself.**
    /// A reply is inserted at the cursor rather than over anything, so it undoes
    /// exactly the way a selection edit does — delete what was put in, from where
    /// it was put in — and calling that "replaced a selection" would be a name
    /// that lies about two thirds of its callers.
    public enum Undo: Equatable, Sendable {
        /// The edit replaced everything the keyboard could see of the field, and
        /// putting it back means replacing it again. Survives the caret moving.
        case wholeField
        /// The edit put `applied` in at the cursor, over a selection or over
        /// nothing. There is no selection left by the time this is read — the
        /// replacement is what consumed it — so the undo counts UTF-16 units back
        /// from where the caret was left.
        case spanAtCursor
    }

    public init(
        origin: Origin,
        previous: String,
        applied: String,
        undo: Undo = .wholeField,
        documentIdentifier: UUID? = nil
    ) {
        self.origin = origin
        self.previous = previous
        self.applied = applied
        self.undo = undo
        self.documentIdentifier = documentIdentifier
    }

    // MARK: - How long the way back lasts

    /// How much the user may write after an edit before the way back is retired.
    ///
    /// **A stated guess, and the only number here that is one.** The expiry that
    /// matters is the safety one and it is exact — the two functions below refuse
    /// unless they can find, in the document, precisely what this edit wrote. This
    /// is the other half: `SuggestionBar` spends a separator and 44pt on the undo
    /// control for as long as it is offered, which is about 52pt off the three
    /// candidate slots, and an undo of a correction from three sentences ago is a
    /// permanent tax on the bar for a decision nobody is still making. Sixty
    /// characters is roughly a line of a chat message: long enough that the wrong
    /// word is still being read in the sentence it landed in, which is when it is
    /// actually noticed, and short enough that the bar is three candidates again
    /// well before the message is finished.
    ///
    /// Counted out of the document rather than out of a keystroke tally, so
    /// there is no counter to increment at every place a keystroke arrives and no
    /// path that can forget to.
    public static let charactersOfTypingAllowed = 60

    /// What the whole field has to become for a `.wholeField` edit to be taken
    /// back, or nil when it can no longer be taken back safely.
    ///
    /// **This is what lets the undo survive typing, and the survival is entirely
    /// in the rebase.** The old rule was that the next keystroke retired the
    /// edit, because `revertEdit` put `previous` back as the whole field and
    /// anything typed since would have gone with it. Locating `applied` inside the
    /// field instead means the characters around it are preserved: type `and one
    /// more thing` after a Fix, take the Fix back, and that clause is still there.
    ///
    /// Three refusals, and each one is a case where taking the undo would destroy
    /// something:
    ///
    /// 1. **Not found.** The user has typed over it, deleted into it, or the host
    ///    has replaced the field. There is nothing to put back and no way to know
    ///    where it would go.
    /// 2. **Found more than once.** A short answer can repeat — `applied` may be a
    ///    single corrected word — and there is no way to tell which occurrence
    ///    this edit wrote. Replacing the wrong one changes a word the user typed.
    /// 3. **Too much written since**, which is `charactersOfTypingAllowed` and is
    ///    about the bar rather than about safety.
    ///
    /// The field this is asked about is `KeyboardController.wholeField`, which is
    /// what the host hands over and is truncated by iOS on a long message. A field
    /// longer than that window fails test 1 and expires, which is the conservative
    /// direction: the undo goes away rather than being offered over text the
    /// keyboard cannot see.
    public func rebased(onto field: String) -> String? {
        guard undo == .wholeField, !applied.isEmpty else { return nil }
        guard let span = onlyOccurrence(of: applied, in: field) else { return nil }
        guard field.count - applied.count <= Self.charactersOfTypingAllowed else { return nil }
        return field.replacingCharacters(in: span, with: previous)
    }

    /// How far back from the caret a `.spanAtCursor` edit has to delete and what
    /// to type in its place, or nil when it can no longer be taken back safely.
    ///
    /// **Two shapes.** Ordinarily what this edit wrote is somewhere in the window
    /// with the user's own characters behind it — none if nothing has been typed
    /// since, which is the case `standsAtEnd(of:)` used to be the whole of. Those
    /// characters are deleted and typed back unchanged either side of the swap,
    /// because `UITextDocumentProxy` deletes backwards from the caret and has no
    /// way to address a range, so reaching the span means passing through them.
    /// The caret ends where it started.
    ///
    /// The second shape is the truncated window: iOS hands back what is near the
    /// cursor and no more, so a clip several lines long — the ordinary thing to
    /// keep in a clipboard history — is longer than anything the keyboard can see,
    /// and everything visible behind the caret is the tail of it. Nothing in that
    /// window says where the edit *began*, so it cannot be rebased and a keystroke
    /// since is one this cannot see around; it is asked second, so an edit that is
    /// locatable takes the branch that preserves what was typed.
    ///
    /// **Two occurrences is a refusal, and that is a real narrowing of
    /// `standsAtEnd(of:)`.** That test was an exact suffix, which is right
    /// whenever nothing has been typed since and wrong the moment something has:
    /// paste `ok`, type ` ok`, and the suffix test happily deletes the copy the
    /// user typed. It could not fire before, because typing retired the edit; it
    /// can now, so the span has to be unambiguous instead. The cost is an undo
    /// silently withheld when the pasted text already stood in the field —
    /// `KeyboardController.expireRevertibleEditIfUnusable` asks the same question,
    /// so the control is not drawn rather than drawn dead.
    /// - Parameter contextAfter: What the field holds *ahead* of the caret, when
    ///   the caller can see it. Defaulted so the tests that ask about the
    ///   before-caret rules alone stay readable.
    ///
    ///   **This closes the one hole the before-caret rules cannot see.** Every
    ///   other way to reach a wrong match is excluded by `onlyOccurrence`: a
    ///   decoy already in the message, or typed later, makes two occurrences and
    ///   the edit is retired at the next refresh. What that reasoning cannot
    ///   exclude is the edit's own span sitting *ahead* of the caret while
    ///   exactly one decoy sits behind it — reachable only with a message long
    ///   enough for iOS to truncate `documentContextBeforeInput`, a caret jump in
    ///   one event, and a token rare enough not to appear a third time. Vanishing
    ///   rather than impossible, and the cost of excluding it outright is a
    ///   conservative refusal when the answer legitimately repeats ahead of the
    ///   caret. A guarantee that holds by construction is worth more than one
    ///   that holds because of how much window iOS happened to hand back.
    public func spanUndo(
        behind contextBefore: String,
        ahead contextAfter: String = ""
    ) -> (delete: Int, insert: String)? {
        guard undo == .spanAtCursor, !applied.isEmpty else { return nil }
        // A legitimate undo has its span behind the caret by construction, so
        // seeing it ahead means the match behind is somebody else's text.
        guard !contextAfter.contains(applied) else { return nil }
        if let span = onlyOccurrence(of: applied, in: contextBefore) {
            let typedSince = String(contextBefore[span.upperBound...])
            guard typedSince.count <= Self.charactersOfTypingAllowed else { return nil }
            return (applied.utf16.count + typedSince.utf16.count, previous + typedSince)
        }
        guard !contextBefore.isEmpty, applied.hasSuffix(contextBefore) else { return nil }
        return (applied.utf16.count, previous)
    }

    /// Where `needle` sits in `haystack`, when it sits there exactly once.
    ///
    /// Searched from both ends rather than counted, because "does it appear
    /// again" is the whole question and one `range(of:)` cannot answer it.
    private func onlyOccurrence(of needle: String, in haystack: String) -> Range<String.Index>? {
        guard let first = haystack.range(of: needle, options: .literal),
            let last = haystack.range(of: needle, options: [.literal, .backwards]),
            first == last
        else { return nil }
        return first
    }
}

// MARK: - Tone

public enum ToneStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case normal
    case clearer
    case shorter
    case professional
    case casual
    case confident

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .normal: return "Normal"
        case .clearer: return "Clearer"
        case .shorter: return "Shorter"
        case .professional: return "Professional"
        case .casual: return "Casual"
        case .confident: return "Confident"
        }
    }

    /// **No tone may wear a sparkle, and Clearer did.** SF `sparkle` and SF
    /// `sparkles` are the same drawing at different counts. These are drawn in
    /// the tone picker and on a result variant, both inside a panel whose header
    /// carries `SparkleMark`, so a sparkle here still puts two of them on one
    /// screen meaning two different things.
    ///
    /// It used to be worse and closer: the one-tap button in `SuggestionBar` wore
    /// this symbol directly beside that bar's own `SparkleMark`, so the shipped
    /// default tone put two sparkles side by side, one running a rewrite and one
    /// opening a panel, and every instruction that named "✨" pointed at both. That
    /// button now wears `SuggestionBar.toneButtonSymbol` and names the tone in
    /// words underneath — see its doc comment for why. `ToneIconTests` holds both
    /// halves of the rule.
    public var icon: String {
        switch self {
        case .normal: return "text.alignleft"
        case .clearer: return "eyeglasses"
        case .shorter: return "arrow.down.right.and.arrow.up.left"
        case .professional: return "briefcase"
        case .casual: return "figure.wave"
        case .confident: return "bolt"
        }
    }

    /// One row per register. Lives on the type so Settings cannot invent a
    /// sample that the prompts do not describe.
    public var previewCaption: String { preview.caption }
    public var previewEnglish: String { preview.english }
    public var previewHebrew: String { preview.hebrew }

    private var preview: (caption: String, english: String, hebrew: String) {
        switch self {
        case .normal:
            return (
                "Keeps your voice. Tidies only what a reader would trip on.",
                "Can you do lunch tomorrow at 12?",
                "אפשר צהריים מחר ב-12?"
            )
        case .clearer:
            return (
                "Drops filler and hedges so the ask is easy to see.",
                "Are you free for lunch tomorrow at 12?",
                "אתה פנוי לצהריים מחר ב-12?"
            )
        case .shorter:
            return (
                "Keeps the same facts in fewer words.",
                "Lunch tomorrow at 12?",
                "צהריים מחר ב-12?"
            )
        case .professional:
            return (
                "Uses full sentences and puts the request as a question.",
                "Would you be available for lunch tomorrow at 12?",
                "האם תהיה פנוי לארוחת צהריים מחר בשעה 12?"
            )
        case .casual:
            return (
                "Sounds like speech, with no formal wording.",
                "Wanna grab lunch tomorrow at 12?",
                "יש לך צהריים מחר ב-12?"
            )
        case .confident:
            return (
                "Goes straight to the point and skips the hedging.",
                "Free for lunch tomorrow at 12?",
                "פנוי לצהריים מחר ב-12?"
            )
        }
    }
}

// MARK: - Fix styles

/// How thoroughly Fix should proofread, picked from a long press on the key.
///
/// **These are not tones.** `Prompts.fix` keeps the writer's register on
/// purpose and `EditScope` undoes any change the model cannot name as a
/// mistake, so pointing a `ToneStyle` at Fix would leave it with nothing to
/// do — that is why the one-tap rewrite key is Rewrite and not Fix. A long
/// press here chooses *which mistakes count*, not how the sentence should
/// sound.
///
/// The default tap is `.proofread`. The other three exist because that pass
/// is conservative on purpose (a lowercase first word stays, a missing full
/// stop stays) and people who want a narrower or a tidier pass have nowhere
/// to ask for one without this list. Titles are what the stacked popup draws,
/// so they have to stay short.
public enum FixStyle: String, CaseIterable, Identifiable, Sendable {
    /// Grammar, spelling and punctuation, writer's register kept. The tap.
    case proofread
    /// Misspellings and jammed words only. Grammar and punctuation stay.
    case spelling
    /// Punctuation and sentence capitals only. Every word stays.
    case punctuate
    /// Proofread, then make the message look finished: capitalise the first
    /// word, end a statement (English) or a question.
    case polish

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .proofread: return "Fix"
        case .spelling: return "Spelling"
        case .punctuate: return "Punctuate"
        case .polish: return "Polish"
        }
    }

    /// Drawn beside the title in the Fix key's hold menu. Looked up by title,
    /// the same way a lift picks a pass, so a renamed case cannot leave a
    /// blank mark next to the old word.
    public var icon: String {
        switch self {
        case .proofread: return "checkmark.circle"
        case .spelling: return "textformat.abc"
        case .punctuate: return "text.quote"
        case .polish: return "paintbrush"
        }
    }

    /// Punctuate and Polish ask for punctuation the model will not name as a
    /// word mistake, so `EditScope.applied` on `none` would throw it away.
    /// Those two styles keep a punctuation-only candidate; the other two do
    /// not, because adding a full stop was never what they asked for.
    var allowsUnnamedPunctuation: Bool {
        self == .punctuate || self == .polish
    }
}
