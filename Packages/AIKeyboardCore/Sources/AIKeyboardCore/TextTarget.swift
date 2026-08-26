import UIKit

// MARK: - Text target

/// Everything the keyboard needs from the document it is typing into.
///
/// `UITextDocumentProxy` satisfies this as-is. The companion app supplies its own
/// implementation so onboarding can show a working keyboard before the real one
/// has been installed.
@MainActor
public protocol TextTarget: AnyObject {
    /// Stable identity for the document currently behind this target.
    ///
    /// Optional because older test and companion conformers cannot identify a
    /// host document. The system proxy does, and that boundary is what prevents
    /// an old undo from editing a new field after iOS reuses the keyboard with
    /// identical text.
    var documentIdentifier: UUID? { get }
    var documentContextBeforeInput: String? { get }
    var documentContextAfterInput: String? { get }
    var selectedText: String? { get }

    /// Whether this is a password field, as the host answered.
    ///
    /// `Bool?` rather than `Bool`, and the optionality is the whole point:
    /// `isSecureTextEntry` is declared inside an `@optional` block of
    /// `UITextInputTraits`, so a host that does not implement it answers nil and
    /// `SecureField` reads nil as "refuse". Anything conforming to this that
    /// positively knows it is not a secure field answers `false`; nothing may
    /// answer `false` to mean "I did not check".
    var isSecureTextEntry: Bool? { get }

    /// The second, independent refusal. `UITextContentType??` because both levels
    /// are real: the outer nil is a host that did not implement the property, the
    /// inner nil is one that implemented it and set nothing.
    var textContentType: UITextContentType?? { get }

    /// What kind of field this is, as the host declared it.
    ///
    /// Optional for the same reason the two above are: `keyboardType` sits in the
    /// same `@optional` block of `UITextInputTraits`, so nil is a host that never
    /// implemented it rather than one that asked for `.default`. Those two mean
    /// the same *behaviour* — `KeyboardController.adoptFieldKeyboardType` leaves
    /// the keyboard exactly as it was for both — and they are still not the same
    /// *fact*, which is what matters when the host swaps fields without the
    /// keyboard going away: a nil arriving mid-session is a `ProxyTextTarget`
    /// whose input view controller has gone, and reading that as a field that
    /// changed its mind would re-decide the plane under a typing finger. Nothing
    /// may answer `.default` to mean "I did not check".
    var keyboardType: UIKeyboardType? { get }

    /// What this field wants automatically capitalised, as the host declared it.
    ///
    /// Same optional shape as `keyboardType` and for the same reason:
    /// `autocapitalizationType` sits in the same `@objc optional` block of
    /// `UITextInputTraits`, so nil is a host that never implemented the property
    /// rather than one that asked for `.sentences`.
    /// `KeyboardController.adoptFieldAutocapitalization` reads that nil exactly
    /// as `.sentences`, which is what this keyboard already did before it read
    /// the trait at all.
    ///
    /// Defaulted to nil by the extension below rather than required outright:
    /// several `TextTarget` conformers inside `AIKeyboardCoreTests` were
    /// written before this trait existed, and answering nil for them — the same
    /// "never checked" reading a silent host gets — is what keeps every one of
    /// them compiling and typing exactly as they did.
    var autocapitalizationType: UITextAutocapitalizationType? { get }

    func insertText(_ text: String)
    func deleteBackward()

    /// Moves the insertion point, without changing the document.
    ///
    /// Here because there is no forward delete: `UITextDocumentProxy` offers
    /// `deleteBackward()` and nothing else, so replacing a sentence the cursor
    /// sits in the middle of means stepping past its tail first and then deleting
    /// the whole span backwards. `replaceTargetText` is the only caller.
    func adjustTextPosition(byCharacterOffset offset: Int)
}

extension TextTarget {
    public var documentIdentifier: UUID? { nil }

    /// The default for every conformer that predates this trait: the same nil
    /// a silent host answers for `keyboardType`.
    public var autocapitalizationType: UITextAutocapitalizationType? { nil }
}

/// Bridges the system proxy to `TextTarget`. `UITextDocumentProxy` is itself a
/// protocol, so it cannot be given a new conformance in an extension.
///
/// **The proxy is resolved per call, not captured once.** `textDocumentProxy` is
/// a `@dynamic` property on `UIInputViewController` and the object behind it is
/// the *current* input document: it is replaced when the host swaps fields, and a
/// copy taken at `viewDidLoad` addresses whichever field happened to be focused
/// then. Holding the input view controller and asking it every time is the only
/// spelling that stays correct across a field change, and it costs an
/// objc_msgSend per keystroke.
///
/// **The resolver may answer nil, and `weak` is why.** `unowned` would be a trap:
/// `KeyView`'s key-repeat is an unstructured `Task` cancelled only from
/// `DragGesture.onEnded`, so a gesture interrupted by teardown leaves a loop
/// calling back into the controller after the input view controller has gone.
/// Against `unowned` that is a crash; against `weak` it is a document that is not
/// there, which is the truth. Every accessor below therefore answers nil rather
/// than substituting a default: nil `isSecureTextEntry` is what `SecureField`
/// reads as *nobody told us*, which is exactly what a vanished host is. That
/// permits rather than refuses — see `SecureField`, where silence permitting is
/// the measured decision — but it is counted as `refusedSecureUnknown` and never
/// mistaken for a host that positively answered.
@MainActor
public final class ProxyTextTarget: TextTarget {
    private let resolve: () -> UITextDocumentProxy?

    private var proxy: UITextDocumentProxy? { resolve() }

    /// Fixed proxy. For callers that hold one directly and have no controller to
    /// ask, which in practice means tests.
    public init(_ proxy: UITextDocumentProxy) {
        self.resolve = { proxy }
    }

    /// The spelling the keyboard extension uses:
    /// `ProxyTextTarget { [weak self] in self?.textDocumentProxy }`.
    public init(resolving: @escaping () -> UITextDocumentProxy?) {
        self.resolve = resolving
    }

    public var documentIdentifier: UUID? { proxy?.documentIdentifier }
    public var documentContextBeforeInput: String? { proxy?.documentContextBeforeInput }
    public var documentContextAfterInput: String? { proxy?.documentContextAfterInput }
    public var selectedText: String? { proxy?.selectedText }

    /// Forwarded exactly as the SDK declares them, optionals and all. Widening
    /// any of these to a non-optional here would put the "unknown permits"
    /// hole back in a place `SecureField`'s tests cannot see.
    public var isSecureTextEntry: Bool? {
        guard let proxy else { return nil }
        return proxy.isSecureTextEntry
    }
    public var textContentType: UITextContentType?? {
        guard let proxy else { return UITextContentType??.none }
        return proxy.textContentType
    }
    public var keyboardType: UIKeyboardType? {
        guard let proxy else { return nil }
        return proxy.keyboardType
    }
    public var autocapitalizationType: UITextAutocapitalizationType? {
        guard let proxy else { return nil }
        return proxy.autocapitalizationType
    }

    public func insertText(_ text: String) { proxy?.insertText(text) }
    public func deleteBackward() { proxy?.deleteBackward() }
    public func adjustTextPosition(byCharacterOffset offset: Int) {
        proxy?.adjustTextPosition(byCharacterOffset: offset)
    }
}

/// An in-memory document, so the companion app can demo the keyboard before the
/// extension is installed.
@MainActor
public final class MockTextTarget: TextTarget, ObservableObject {
    @Published public var text: String
    public let documentIdentifier: UUID?

    public init(text: String = "", documentIdentifier: UUID? = UUID()) {
        self.text = text
        self.documentIdentifier = documentIdentifier
    }

    public var documentContextBeforeInput: String? { text }
    public var documentContextAfterInput: String? { "" }
    public var selectedText: String? { nil }

    /// A positive `false`, not a shrug. This is a `String` in this process with
    /// no secure-entry behaviour anywhere near it, so it answers the question
    /// rather than declining to — which is what keeps the in-app playground and
    /// onboarding working under a guard that refuses on silence.
    public var isSecureTextEntry: Bool? { false }
    public var textContentType: UITextContentType?? { .some(.none) }

    /// A positive `.default`, on the same principle as the line above: the
    /// playground genuinely is an ordinary free-text document, so it answers the
    /// question rather than declining to.
    ///
    /// **Stored rather than computed, because the one thing a real host does that
    /// no fixed value can model is *change*.** Moving focus between two fields
    /// without the keyboard going away is a new `keyboardType` on the same proxy,
    /// and that is the path `adoptFieldKeyboardType` has to get right; a test has
    /// no other way to reach it.
    public var keyboardType: UIKeyboardType? = .default

    /// A positive `.sentences`, on the same principle as `keyboardType`: the
    /// playground is an ordinary free-text document and answers the question
    /// rather than declining to. Stored rather than computed for the same
    /// reason `keyboardType` is: a test drives a field swap by changing it on
    /// the same target.
    public var autocapitalizationType: UITextAutocapitalizationType? = .sentences

    public func insertText(_ newText: String) { text.append(newText) }
    public func deleteBackward() { if !text.isEmpty { text.removeLast() } }
    /// No-op, and honestly so: this document has no cursor to move, which is why
    /// `documentContextAfterInput` is always empty. There is never a tail to step
    /// over here.
    public func adjustTextPosition(byCharacterOffset offset: Int) {}
}
