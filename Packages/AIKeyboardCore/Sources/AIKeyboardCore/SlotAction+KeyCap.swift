import Foundation

// MARK: - Compiling one slot

public extension SlotAction {

    /// The cap this action draws as.
    ///
    /// Optional rather than non-optional so `testEveryCatalogueActionHasAKeyCap`
    /// can fail loudly if a case is ever added to the enum and forgotten here.
    /// Nothing returns nil today.
    func keyCap(language: KeyboardLanguage) -> KeyCap? {
        switch self {
        case .shift: return .shift
        case .backspace: return .backspace
        case .numbersPlane: return .plane(.numbers, label: "123")
        case .symbolsPlane: return .plane(.symbols, label: "#+=")
        case .globe: return .globe
        case .settings: return .settings
        case .space: return .space
        case .ret: return .ret
        case .dictation: return .dictation
        case .emoji: return .emoji
        case .copyclip: return .copyclip
        case .quickTone: return .quickTone
        case .cursorLeft: return .cursorLeft
        case .cursorRight: return .cursorRight
        case .deleteForward: return .deleteForward
        case .hideKeyboard: return .hideKeyboard
        case .reply: return .aiReply
        case .fix: return .aiFix
        // Its cap is the script's own mark, and the alternates that come with it
        // live on the `KeySpec` rather than the `KeyCap`, so the compiler builds
        // this one whole through `KeyboardLayout.punctuationKey(for:)`. Answered
        // here too, because callers that only want to know what it draws (the
        // editor's drawer, the bar) ask this.
        case .punctuation:
            return KeyboardLayout.punctuationKey(for: language).cap
        case .text(let value): return .character(value)
        }
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
        case .shift: return "shift"
        case .backspace: return KeyCap.backspaceSymbol(isRightToLeft: isRightToLeft)
        case .numbersPlane, .symbolsPlane: return nil
        case .globe: return "globe"
        case .settings: return "gearshape"
        case .space: return "space"
        case .ret: return "return"
        case .dictation: return "waveform"
        case .emoji: return "face.smiling"
        case .copyclip: return "clipboard"
        case .quickTone: return AIAction.rewrite.icon
        // Each action's own icon, so the key and the banner's label draw one thing.
        case .reply: return AIAction.reply.icon
        case .fix: return AIAction.fix.icon
        case .cursorLeft: return KeyCap.cursorLeftSymbol(isRightToLeft: isRightToLeft)
        case .cursorRight: return KeyCap.cursorRightSymbol(isRightToLeft: isRightToLeft)
        case .deleteForward: return KeyCap.deleteForwardSymbol(isRightToLeft: isRightToLeft)
        case .hideKeyboard: return "keyboard.chevron.compact.down"
        case .punctuation, .text: return nil
        }
    }
}
