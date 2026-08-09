import Foundation

// MARK: - The tone

/// The tone the keyboard rewrites in when nobody picks one: one of the six
/// built-in registers, or a short instruction the user wrote themselves.
///
/// It sits beside `ToneStyle` rather than inside it. `ToneStyle` is a
/// `String`-backed enum whose raw values *are* the persisted setting and whose
/// cases are the chips in the tone panel; a case carrying a payload would change
/// both. Everything that only needs a register keeps taking `ToneStyle`, and this
/// is what the parts that have to honour a user-authored tone take.
public enum ToneSetting: Equatable, Sendable {
    case builtIn(ToneStyle)

    /// One line the user wrote, plus the built-in register that stands in for it
    /// where it cannot be used.
    ///
    /// **`nearest` is not a guess at what the sentence means.** It is the built-in
    /// the user last chose from the list, which is the only second choice this code
    /// can honestly know. `instruction` now reaches the prompt —
    /// `Prompts.tone(_:for:instruction:)` composes it and
    /// `TextIntelligence.variants(for:tone:instruction:)` carries it — and
    /// `nearest` is what runs in the one case that is left:
    /// `FoundationModelsEngine` drops a register written in a script Apple's model
    /// does not list rather than open a session it would reject outright.
    case custom(instruction: String, nearest: ToneStyle)

    /// The register the answer is *labelled* with, and the one an engine falls
    /// back to when it cannot honour the user's own words. Not the instruction:
    /// that travels beside it, in `instruction`.
    public var style: ToneStyle {
        switch self {
        case .builtIn(let tone): return tone
        case .custom(_, let nearest): return nearest
        }
    }

    /// The user's own words, or nil for a built-in register.
    public var instruction: String? {
        switch self {
        case .builtIn: return nil
        case .custom(let instruction, _): return instruction
        }
    }

    public var title: String {
        switch self {
        case .builtIn(let tone): return tone.title
        case .custom: return Self.customTitle
        }
    }

    public var icon: String {
        switch self {
        case .builtIn(let tone): return tone.icon
        case .custom: return "square.and.pencil"
        }
    }

    /// Named once so the settings picker and the keyboard cannot drift apart.
    public static let customTitle = "My tone"

    /// What Settings prints under the field where the user writes their own tone.
    ///
    /// **Here rather than in the view because it names a control, and it named the
    /// wrong one.** It used to say "the ✦ button above the keys". Nothing in this
    /// keyboard draws ✦: the suggestion bar has two brand-tinted buttons side by
    /// side, one wearing the *tone's own* SF Symbol and one wearing `sparkles`, and
    /// a user following that sentence tapped the sparkle, which opens the AI menu
    /// and does not run their tone. It cannot be named by a glyph at all — the icon
    /// changes with the tone — so it is named by what it does, and the same words
    /// are `SuggestionBar.toneButton`'s accessibility hint.
    ///
    /// The second branch is the one worth being careful about. The line the user
    /// writes does reach the model now, but not in every pairing: the two
    /// instruction sets are never mixed, so a register written in Hebrew is dropped
    /// when the message being rewritten is English, and the built-in register runs
    /// instead. Saying nothing would leave a Hebrew-speaking user watching their own
    /// words be quietly ignored. See `Prompts.tone`.
    public var settingsNote: String {
        switch self {
        case .builtIn(let tone):
            return "Write one line and the one-tap rewrite button above the keys uses it. Until then it "
                + "rewrites as \(tone.title)."
        case .custom(_, let nearest):
            return "The one-tap rewrite button above the keys writes in this register. On a message in a "
                + "different language from the line above — a Hebrew tone over an English sentence — it "
                + "falls back to \(nearest.title), because mixing two languages in one instruction makes a "
                + "model answer in the wrong one."
        }
    }
}

// MARK: - Where it is stored

extension SharedStore {

    /// Long enough for a sentence, short enough that what the user wrote stays a
    /// register and does not become a second set of instructions. The text is
    /// destined for a model prompt, so it is bounded where it is written rather
    /// than where it is read.
    public static let customToneLimit = 120

    /// The instruction the user typed, exactly as they typed it.
    ///
    /// Written through `userDefaults` because this file cannot add a stored
    /// property to `SharedStore`; `objectWillChange.send()` is what a `@Published`
    /// would have done for it. Reaching for `.standard` instead would work in the
    /// app, be private to the extension in the keyboard, and fail silently in
    /// exactly one of the two processes — the bug `BackendTransport.configured`
    /// already shipped once.
    public var customTone: String {
        get { userDefaults.string(forKey: Key.customToneInstruction) ?? "" }
        set {
            objectWillChange.send()
            userDefaults.set(
                String(newValue.prefix(Self.customToneLimit)), forKey: Key.customToneInstruction)
        }
    }

    /// Whether the default tone is the user's own rather than one of the six.
    ///
    /// Kept separate from the text so switching back to a built-in register does
    /// not throw away what the user wrote.
    public var prefersCustomTone: Bool {
        get { userDefaults.bool(forKey: Key.prefersCustomTone) }
        set {
            objectWillChange.send()
            userDefaults.set(newValue, forKey: Key.prefersCustomTone)
        }
    }

    /// The stored register, read back rather than taken off the `@Published` copy.
    ///
    /// Settings runs in the *other* process, and `load()` fills the published
    /// properties once, when whichever process asked was launched. A keyboard that
    /// is already up would otherwise keep answering with the tone that was stored
    /// when it started, which is the same staleness the two accessors above avoid
    /// by reading through `userDefaults`. Falls back to the published value, which
    /// is the shipped default until something writes one.
    private var storedDefaultTone: ToneStyle {
        userDefaults.string(forKey: Key.defaultTone).flatMap(ToneStyle.init(rawValue:))
            ?? defaultTone
    }

    /// The tone the one-tap rewrite runs in.
    ///
    /// An empty instruction is not a tone: preferring a custom tone that has not
    /// been written yet answers with the built-in rather than sending the model a
    /// register with nothing in it.
    public var toneSetting: ToneSetting {
        let nearest = storedDefaultTone
        let instruction = Self.oneLine(customTone)
        guard prefersCustomTone, !instruction.isEmpty else { return .builtIn(nearest) }
        return .custom(instruction: instruction, nearest: nearest)
    }

    /// One line, with runs of whitespace collapsed.
    ///
    /// The instruction is pasted into a model's *instructions*, where a newline is
    /// where a second instruction would start. The user is the only person who can
    /// write here and the only person it could mislead, so this is a tidy-up rather
    /// than a security boundary — but a register that spans three lines is not a
    /// register, and neither is one that ends in a paragraph of its own.
    static func oneLine(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
