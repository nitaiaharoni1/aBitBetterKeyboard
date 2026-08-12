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

/// A Fix or Rewrite that was written straight into the field, and the text it
/// replaced.
///
/// **Fix and Rewrite apply themselves now, so undo is not a nicety.** They used
/// to put an answer in the banner behind a Use button, which made accepting the
/// change the user's own act; applying it on arrival is faster and reads better —
/// the correction appears in the sentence rather than beside it — but it also
/// means the keyboard has changed somebody's message without being asked twice.
/// `UITextDocumentProxy` has no undo of any kind, so the only way back is to have
/// kept what was there.
///
/// `applied` is held as well as `previous` because the revert has to delete
/// exactly what was inserted: the field may be a different length by then only if
/// the user typed, and typing is what clears this.
public struct AIEdit: Equatable, Sendable {
    public let action: AIAction
    /// What the span the action replaced held before it ran. Read at the moment
    /// of the replacement rather than at the moment the call started, so it is
    /// what was *actually* taken out even if the field moved while the model was
    /// thinking.
    public let previous: String
    /// What the action put there.
    public let applied: String

    /// **Whether the action replaced a selection rather than the whole field, and
    /// this is not bookkeeping.** The two undo differently and getting it wrong
    /// destroys the user's message: a Fix over the selected word `wrold` in
    /// `hello there wrold friend` replaces five characters, and a revert that put
    /// `previous` back the way a whole-field edit does would leave the field
    /// holding the single word `wrold`. See `KeyboardController.revertAIEdit`.
    public let replacedSelection: Bool

    public init(
        action: AIAction, previous: String, applied: String, replacedSelection: Bool = false
    ) {
        self.action = action
        self.previous = previous
        self.applied = applied
        self.replacedSelection = replacedSelection
    }
}

// MARK: - Tone

public enum ToneStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case clearer
    case shorter
    case professional
    case casual
    case confident
    case friendly

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .clearer: return "Clearer"
        case .shorter: return "Shorter"
        case .professional: return "Professional"
        case .casual: return "Casual"
        case .confident: return "Confident"
        case .friendly: return "Friendly"
        }
    }

    /// **No tone may wear a sparkle, and Clearer did.** SF `sparkle` and SF
    /// `sparkles` are the same drawing at different counts. These six are drawn in
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
        case .clearer: return "eyeglasses"
        case .shorter: return "arrow.down.right.and.arrow.up.left"
        case .professional: return "briefcase"
        case .casual: return "figure.wave"
        case .confident: return "bolt"
        case .friendly: return "hand.wave"
        }
    }
}
