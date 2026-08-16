import Foundation

// MARK: - AI actions

public enum AIAction: String, CaseIterable, Identifiable, Hashable, Sendable {
    /// Answers the message on screen. Only useful while a screen context session
    /// is running, so it leads the menu and explains itself when it cannot run.
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
        case .reply: return "Answer what's on screen"
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

    /// Reply reads the screen; everything else only reads the text field.
    public var needsScreenContext: Bool { self == .reply }

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
        needsScreenContext ? true : hasTextToWorkWith
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
/// Its lifetime is identical too — until the next keystroke — so a second slot
/// beside this one would be a second thing to clear from the seventeen places
/// `clearRevertibleEdit()` is already called from, and the first one anybody
/// forgot would delete characters the user typed. One slot, one step, one
/// implementation of "delete exactly what was put in, from where it was put in".
///
/// `applied` is held as well as `previous` because the revert has to delete
/// exactly what was inserted: the field may be a different length by then only if
/// the user typed, and typing is what clears this.
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

        /// What the undo control is called out loud. It names the action rather
        /// than saying "Undo", for the reason `SuggestionBar.revertButton` gives:
        /// the field has already changed by the time anybody reads it.
        public var undoLabel: String {
            switch self {
            case .ai(let action): return "Undo \(action.title)"
            case .clip: return "Undo paste"
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

    public init(origin: Origin, previous: String, applied: String, undo: Undo = .wholeField) {
        self.origin = origin
        self.previous = previous
        self.applied = applied
        self.undo = undo
    }

    /// Whether what this edit put in is still standing at the cursor, which is
    /// the claim `.spanAtCursor` deletes a count of units on.
    ///
    /// **Two tests, because `documentContextBeforeInput` is a window and not the
    /// field.** iOS hands back what is near the cursor and no more, so a clip
    /// several lines long — the ordinary thing to keep in a clipboard history —
    /// is longer than anything the keyboard can see, and the exact test alone
    /// answers false on an edit that is perfectly intact. The second test is the
    /// same claim asked of a truncated window: everything visible behind the
    /// cursor is the tail of what this edit wrote, so none of it belongs to the
    /// user. An empty window is refused rather than accepted, because `""` is a
    /// suffix of every string and deleting a count from a field the keyboard
    /// cannot see is the one outcome worse than no undo at all.
    public func standsAtEnd(of contextBefore: String) -> Bool {
        if contextBefore.hasSuffix(applied) { return true }
        return !contextBefore.isEmpty && applied.hasSuffix(contextBefore)
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
