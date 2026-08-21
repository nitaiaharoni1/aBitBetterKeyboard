import Foundation
import UIKit

extension ScreenContextSession {

    // MARK: - The secure-field guard

    /// Whether Reply may ask for a read of a field with these traits, leaving a
    /// number behind either way.
    ///
    /// The decision is `SecureField.permitsRead`, which is a pure truth table and
    /// is tested as one. What is here is the half that cannot be pure: the
    /// decision has to leave a count behind, or the open question this guard
    /// rests on — whether any host populates `isSecureTextEntry` through a
    /// `UITextDocumentProxy` at all — stays folklore. It counts **every**
    /// decision and not only the refusals, because silence permits, so a count
    /// that only moved on a refusal could not tell a silent host from one
    /// answering "not secure".
    ///
    /// **For its whole life that number went somewhere nobody could read, and
    /// this is where it goes now.** `countSecureDecision` lands in
    /// `CaptureIntent.refusedSecure` through `CaptureChannelReader`, and nothing
    /// in this repository reads those fields back — not the app, not the
    /// broadcast extension, not Settings, not `Bar/screen-context`. Inspecting
    /// them means dumping the mmap'd shared page by hand, which nobody has a tool
    /// for. On top of that, `channel` is set by `startConsuming` and by nothing
    /// else, and that call is gated on `FeatureFlags.screenCaptureReply` in both
    /// processes, so in a v1 build it cannot move at all. Two independent reasons
    /// the measurement did not exist. NIT-187 is the issue.
    ///
    /// `SecureDecisionRecord` is the answer: a boot-scoped App Group record with
    /// a Settings → Diagnostics row, independent of the capture channel and
    /// therefore of the flag. **It is reached on every Reply tap that has
    /// something to reply to**, and Reply ships in v1 sourced from the
    /// pasteboard, so it fills up on an ordinary phone rather than waiting for a
    /// feature nobody has switched on. The qualifier is not pedantry:
    /// `runReply`'s `guard let source = replySource` sits *above* this call, and
    /// in a v1 build `replySource` reduces to the clipboard, so a Reply tap with
    /// an empty CopyClip ledger is refused before any decision is taken and
    /// nothing is counted.
    ///
    /// **Both writes stay, and the channel one is the secondary copy.** It is one
    /// line, it is a no-op while `channel` is nil, and it is a named Phase 7
    /// deliverable of the capture design (`screen-capture-design.md`, R14) with a
    /// test on it. Deleting it to remove a duplicate would quietly drop that. The
    /// record is the one to read.
    ///
    /// The two refusal reasons are derived by `Decision.taken(secure:permitted:)`
    /// rather than spelled out here, so the exclusivity `permitted` depends on is
    /// a property of the type rather than of this call site's discipline.
    @discardableResult
    public func permitsRead(secure: Bool?, contentType: UITextContentType??) -> Bool {
        let permitted = SecureField.permitsRead(secure: secure, contentType: contentType)
        SecureDecisionRecord.note(.taken(secure: secure, permitted: permitted))
        channel?.countSecureDecision(
            refused: !permitted, unanswered: !SecureField.answered(secure: secure))
        return permitted
    }

    // MARK: - Reply

    /// The reading Reply may act on, waiting for a fresh one if it has to.
    ///
    /// **It refuses rather than guesses, and that is the whole point of it.**
    /// There is one trigger for a read and it is this tap, so the ordinary case
    /// is that no reading exists yet: the channel gets `intent.readNow` raised
    /// and this waits for a record that answers *that* number and that
    /// `CaptureFreshness` calls offerable. A reading the gate has refused —
    /// superseded by a scrolled or switched conversation, unconfirmed, or older
    /// than the backstop — is never returned, at any point in here. A five
    /// second wait is the honest answer; a reply in the user's own name about
    /// somebody else's message is not.
    ///
    /// The scripted demo short-circuits: its reading is the fiction the
    /// playground is built on and there is no channel to ask.
    public func contextForReply(timeout: Duration = .seconds(12)) async throws -> ScreenContext {
        if source == .scripted, let context = state.context { return context }

        // The app is an observer: it watches the page so its Screen Context
        // screen can be honest, but it is not the keyboard and its preview is not
        // at the bottom of anyone's screen. A read raised from the in-app
        // playground would photograph *this app* — our own playground, with our
        // own animation inside the fingerprint band — and answer a question
        // nobody asked. The sample is what the playground is for, and it is
        // handled above; anything else is refused rather than read.
        guard role == .keyboard else {
            throw AIEngineError.screenNotRead(
                "Reading the screen works in the keyboard, on the app you are writing in.")
        }

        guard let channel else {
            throw AIEngineError.screenNotRead("Screen context is not running.")
        }

        // Freshness is decided at the instant of the tap, never against the last
        // poll, which may be 250 ms old and about the previous conversation.
        channel.poll()
        if channel.verdict == .offerable, let record = channel.reading {
            lastReadWentUnanswered = false
            return record.screenContext
        }

        let sequence = channel.requestRead()
        guard sequence > 0 else {
            throw AIEngineError.screenNotRead(
                "The keyboard cannot reach screen context. It needs Full Access.")
        }

        isAwaitingRead = true
        defer { isAwaitingRead = false }

        // `try`, not `try?`. Swallowing the cancellation here left nothing pacing
        // this loop but the deadline: a cancelled Reply became ~16,000 polls per
        // second, each one a file read, a JSON decode and a SwiftUI invalidation
        // on the main actor, for the rest of the timeout, inside a process capped
        // near 48 MB. Measured at 31,588 polls in 2 s against 6 in the healthy
        // case. And it is the ordinary path rather than an unlucky one: while the
        // capture process runs no reader, every Reply times out, so tapping it
        // again is exactly what a user does. `beginWork` cancels the previous
        // task on every new action, and both of its catch arms already return
        // early on cancellation, so letting this throw is all that is needed.
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(200))
            channel.poll()

            // A read that answered and failed is an answer. Without this the
            // capture process publishes "no backend configured" or "the network
            // went away" and the user still waits out the full timeout, then gets
            // told nothing answered — which is now the wrong reason as well as a
            // slow one. The gate deliberately refuses to call a non-`.read`
            // record offerable, so this has to be asked before the verdict.
            if let record = channel.reading,
                record.requestSequence >= sequence,
                record.outcome != .read
            {
                // **A failure that describes the setup is not cleared, it is
                // raised.** A rejected token or an address that is not this
                // service fails identically on the next tap, and clearing the
                // flag put "Reply can read this screen" straight back on the
                // strip — so every further tap spent another upload of the user's
                // screen to be told the same thing. See
                // `ScreenReadService.describesSetup`.
                lastReadWentUnanswered = ScreenReadService.describesSetup(record.detail)
                throw AIEngineError.screenNotRead(record.failureExplanation)
            }

            switch channel.verdict {
            case .offerable:
                if let record = channel.reading, record.requestSequence >= sequence {
                    lastReadWentUnanswered = false
                    return record.screenContext
                }
            case .ended(let reason):
                throw AIEngineError.screenNotRead(reason.explanation)
            case .noSession:
                throw AIEngineError.screenNotRead("Screen context is not running.")
            case .starting, .paused, .idle, .unconfirmed, .superseded:
                continue
            }
        }

        // The reason names what happened rather than a cause it did not check.
        lastReadWentUnanswered = true
        throw AIEngineError.screenNotRead(
            "Screen context is watching, but nothing answered the request to read the screen.")
    }

    // MARK: - Frames handed in directly

    /// Hands one captured frame to the reader.
    ///
    /// The in-app path: the containing app holds the frame, so no extension
    /// memory cap applies and `RoutedScreenReader` may keep an English screen on
    /// device. The capture flow does not come through here — its frames never
    /// reach this process, only the text read off them does — which is why this
    /// is the only place `reader` is used.
    public func submit(_ frame: CGImage, appName: String, appIcon: String) async {
        guard let reader, state.isLive else { return }
        framesRead += 1

        do {
            let output = try await reader.read(frame)
            guard let reading = output.value else {
                // A screen with nothing to reply to is a real answer. The strip
                // goes back to watching rather than offering a stale reply.
                if state.context != nil { state = .watching }
                return
            }
            state = .ready(
                ScreenContext(
                    appName: appName,
                    appIcon: appIcon,
                    sender: reading.sender,
                    message: reading.message,
                    language: reading.language))
        } catch {
            // A frame that could not be read is not worth telling the user
            // about: another one arrives in a moment. Only a session that never
            // reads anything is worth surfacing, and that shows as `.watching`.
            state = state.context == nil ? .watching : state
        }
    }
}
