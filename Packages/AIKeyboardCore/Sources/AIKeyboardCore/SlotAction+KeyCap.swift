import Foundation

// MARK: - Compiling one slot

public extension SlotAction {
    private static let simpleCaps: [SlotAction: KeyCap] = [
        .shift: .shift, .backspace: .backspace, .globe: .globe, .settings: .settings,
        .space: .space, .ret: .ret, .dictation: .dictation, .emoji: .emoji,
        .copyclip: .copyclip, .quickTone: .quickTone, .cursorLeft: .cursorLeft,
        .cursorRight: .cursorRight, .deleteForward: .deleteForward,
        .hideKeyboard: .hideKeyboard, .reply: .aiReply, .fix: .aiFix
    ]
    private static let simpleGlyphs: [SlotAction: String] = [
        .shift: "shift", .globe: "globe", .settings: "gearshape", .space: "space",
        .ret: "return", .dictation: "waveform", .emoji: "face.smiling",
        .copyclip: "clipboard", .quickTone: AIAction.rewrite.icon,
        .reply: AIAction.reply.icon, .fix: AIAction.fix.icon,
        .hideKeyboard: "keyboard.chevron.compact.down"
    ]

    /// The cap this action draws as.
    ///
    /// Optional rather than non-optional so `testEveryCatalogueActionHasAKeyCap`
    /// can fail loudly if a case is ever added to the enum and forgotten here.
    /// Nothing returns nil today.
    func keyCap(language: KeyboardLanguage) -> KeyCap? {
        switch self {
        case .numbersPlane: return .plane(.numbers, label: "123")
        case .symbolsPlane: return .plane(.symbols, label: "#+=")
        // Its cap is the script's own mark, and the alternates that come with it
        // live on the `KeySpec` rather than the `KeyCap`, so the compiler builds
        // this one whole through `KeyboardLayout.punctuationKey(for:)`. Answered
        // here too, because callers that only want to know what it draws (the
        // editor's drawer, the bar) ask this.
        case .punctuation:
            return KeyboardLayout.punctuationKey(for: language).cap
        case .text(let value): return .character(value)
        default: return simpleKeyCap
        }
    }

    private var simpleKeyCap: KeyCap? {
        Self.simpleCaps[self]
    }

    /// Whether this key draws its name under its glyph, and so has a label the
    /// editor can offer to hide.
    ///
    /// Exactly the six `KeyView+Label` draws through `actionLabel`. Every other
    /// cap is a glyph or a character that *is* its own name — the return arrow,
    /// the full stop, `123` — so hiding "the label" would leave a blank key.
    var hasLabel: Bool {
        switch self {
        case .dictation, .emoji, .copyclip, .quickTone, .reply, .fix: return true
        default: return false
        }
    }

    /// The SF Symbol the editor's drawer draws beside the name. A `.text` action
    /// and the two plane keys draw their own characters instead, which is why
    /// this is optional. Cursor and delete names follow `isRightToLeft`; the
    /// editor defaults false.
    func glyph(isRightToLeft: Bool = false) -> String? {
        switch self {
        case .backspace: return KeyCap.backspaceSymbol(isRightToLeft: isRightToLeft)
        case .numbersPlane, .symbolsPlane: return nil
        case .cursorLeft: return KeyCap.cursorLeftSymbol(isRightToLeft: isRightToLeft)
        case .cursorRight: return KeyCap.cursorRightSymbol(isRightToLeft: isRightToLeft)
        case .deleteForward: return KeyCap.deleteForwardSymbol(isRightToLeft: isRightToLeft)
        case .punctuation, .text: return nil
        default: return simpleGlyph
        }
    }

    private var simpleGlyph: String? {
        Self.simpleGlyphs[self]
    }
}
