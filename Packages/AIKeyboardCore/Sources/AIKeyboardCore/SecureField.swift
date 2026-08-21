import UIKit

/// Whether a read of the screen may fire while the user is typing into *this*
/// field.
///
/// A privacy rule rather than a resource one, and the only refusal in the design
/// that is about what is on screen rather than about what the capture process can
/// afford: **never ask for a read while the focused field is a secure text entry
/// field.** A password typed into a banking app is on the screen the read would
/// upload.
///
/// **It refuses on a positive yes, and permits on silence — deliberately, and
/// against the design's original spelling.** An earlier version treated `nil` as
/// a refusal on the reasoning that a guard permitting by default is not a guard.
/// That is sound in general and wrong here, for two measured reasons:
///
/// 1. **iOS already prevents the case this guards.** From Apple's App Extension
///    Programming Guide: *"When a user taps in a secure text input object, the
///    system temporarily replaces your custom keyboard with the system
///    keyboard."* This keyboard is never on screen for a password field, so
///    `isSecureTextEntry == true` is a branch that essentially cannot fire while
///    anything here is running.
/// 2. **`nil` is not evidence of danger.** The protocol chain is real —
///    `UITextDocumentProxy` conforms to `UIKeyInput`
///    (`UIInputViewController.h:19`) which conforms to `UITextInputTraits`
///    (`UITextInput.h:24`) — but the declaration sits inside an `@optional`
///    block (`:239` opens it, `secureTextEntry` is at `:257`), so in Swift it is
///    `Bool?`. Verified by compiling against `iPhoneSimulator26.2.sdk`:
///
///    ```
///    error: cannot convert value of type 'Bool?' to specified type 'Never'
///    error: cannot convert value of type 'UITextContentType??' to specified type 'Never'
///    ```
///
///    `nil` means the host did not implement an optional protocol member. It does
///    not mean "this is a password field."
///
/// Refusing on `nil` therefore guards a case the OS already handles, and pays for
/// it by disabling Reply on every host that answers `nil` — which, until a device
/// says otherwise, may be all of them. The count survives so that question stays
/// measurable, and **it is `SecureDecisionRecord` that answers it**, not the
/// channel counters this comment used to point at: those land in
/// `CaptureIntent.refusedSecure`, which nothing in this repository reads back and
/// which cannot move at all while `FeatureFlags.screenCaptureReply` is false. The
/// record is boot-scoped, independent of that flag, and has a Settings →
/// Diagnostics row. `answered` sitting at zero against a large `decisions` is how
/// you learn no host ever answers.
///
/// **Do not mistake this for the thing that protects sensitive screens.** A read
/// uploads the whole screen, not the focused field, so a password manager visible
/// behind an ordinary search box is not caught here at all. What protects the
/// user is that there is no speculative read: a frame leaves only in answer to a
/// tap. This is narrow defence in depth on top of that, and it is free.
///
/// **It guards two things now, and only one of them is a read.** Since Reply's
/// message can come from the clipboard (`ReplySource`), the ordinary case
/// photographs nothing at all — and the guard still refuses, because Reply
/// *inserts*, and writing a generated sentence into a credential field is wrong
/// whatever the sentence was written about. `KeyboardController.runReply` is
/// where that second half is spelled out; the truth table below is unchanged.
public enum SecureField {

    /// Three rules, and they are the design rather than an implementation
    /// detail.
    ///
    /// 1. **Only a positive `true` refuses.** Silence permits, because silence
    ///    is an unimplemented optional protocol member rather than a password
    ///    field, and because iOS never shows this keyboard for one. See above.
    /// 2. **`textContentType` is a second, independent refusal and never a
    ///    permission.** It is `UITextContentType??`: the outer `nil` means the
    ///    host did not implement the property, the inner `nil` means it
    ///    implemented it and set nothing. Neither is evidence of safety, so both
    ///    fall through to whatever `isSecureTextEntry` said, and a value in
    ///    `sensitive` refuses on its own even when the field claims not to be
    ///    secure.
    /// 3. **A refusal is counted and named**, separately for the two reasons, and
    ///    so is every decision that is *not* a refusal — silence permits, so a
    ///    count that moved only on refusals could not tell a silent host from one
    ///    saying "not secure". `SecureDecisionRecord` is where that lands and
    ///    where it can be read; `CaptureIntent.refusedSecure` is the older copy
    ///    and goes nowhere.
    public static func permitsRead(secure: Bool?, contentType: UITextContentType??) -> Bool {
        guard secure != true else { return false }
        guard let inner = contentType, let type = inner else { return true }
        return !sensitive.contains(type)
    }

    /// Whether the host answered the question at all, which is the single most
    /// useful thing this file can measure.
    ///
    /// `SecureDecisionRecord.answered` is the running count. Zero against a large
    /// `decisions` says no host populates the trait through a
    /// `UITextDocumentProxy`, which would mean the `secure == true` branch above
    /// is unreachable in practice and "silence permits" is the whole of the
    /// rule.
    public static func answered(secure: Bool?) -> Bool { secure != nil }

    /// The five constants verified in `UITextInputTraits.h:305-309` and `:324` of
    /// `iPhoneOS26.2.sdk`. Deliberately short: this list refuses, so every entry
    /// costs a screen the user asked to have read, and only fields whose content
    /// is a credential belong in it.
    public static let sensitive: Set<UITextContentType> = [
        .password, .newPassword, .oneTimeCode, .creditCardNumber, .creditCardSecurityCode
    ]
}
