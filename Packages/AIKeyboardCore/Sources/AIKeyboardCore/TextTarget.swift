import UIKit

// MARK: - Text target

/// Everything the keyboard needs from the document it is typing into.
///
/// `UITextDocumentProxy` satisfies this as-is. The companion app supplies its own
/// implementation so onboarding can show a working keyboard before the real one
/// has been installed.
@MainActor
public protocol TextTarget: AnyObject {
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

    public init(text: String = "") {
        self.text = text
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

    public func insertText(_ newText: String) { text.append(newText) }
    public func deleteBackward() { if !text.isEmpty { text.removeLast() } }
    /// No-op, and honestly so: this document has no cursor to move, which is why
    /// `documentContextAfterInput` is always empty. There is never a tail to step
    /// over here.
    public func adjustTextPosition(byCharacterOffset offset: Int) {}
}
