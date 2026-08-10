import Foundation

// MARK: - Error messages and explain

extension ScreenReadService {

    // **These exist because `AIEngineError.message` is written for the text
    // engine, and on this path three of its sentences are false.** `CloudIntelligence`
    // and `CloudScreenReader` share one transport, so they share
    // `BackendTransport.mapped`, so a 401 from the screen-reading backend arrives
    // here as `.cloudNotConfigured` — whose message is "This language needs a
    // cloud model, and none is set up in this build." There is no language in a
    // screen read, and by the time a 401 is possible a cloud model *is* set up:
    // the user typed its address into `ScreenContextView`, which is the screen
    // that would have to be reopened to fix the token. 413 and 422 are the same
    // bug on the same switch — "Select a shorter passage" and "Editing it
    // slightly usually gets past it" are instructions about a passage of text
    // nobody selected.
    //
    // The mapping lives here rather than in `AIEngineError` because the enum is
    // shared with the text path, where those three sentences are correct.

    /// What the strip says when the build has no backend. The same sentence
    /// whether the tap is refused before a read or fails at the start of one.
    public static let notConfigured = "Screen reading is not set up in this build."

    /// 401 or 403 — the address is right and the credential is not.
    ///
    /// **Stopped telling people to check a token when there stopped being one to
    /// check.** The bearer is written by `AppAttestation` now, not typed, and the
    /// field it named is compiled out of Release, so "check it in Screen Context"
    /// sent a user looking for a box that is not there. A 401 here means the same
    /// two things it means for `AIEngineError.cloudNotConfigured`: attestation has
    /// never run because the app has had no network since install, or the token it
    /// wrote has expired. Opening the app is what fixes both.
    public static let tokenRejected =
        "The screen reading server turned this app away. Open AI Keyboard once to reconnect."

    /// A non-200 the backend did not describe: usually a 404, i.e. a host that
    /// exists and is not running this service.
    public static let addressNotAServer =
        "That address answered, but not like the screen reading server. Check the address in AI Keyboard › Screen Context."

    /// Whether a published failure describes the **setup** rather than this
    /// moment, and will therefore fail identically on the next tap.
    ///
    /// **The keyboard needs this and the record has nowhere to put it.**
    /// `ScreenReadOutcome` has one failure case and `ScreenReadingRecord.detail`
    /// is a sentence, so "will this repeat" has no field of its own — and without
    /// it the strip goes straight back to "Reply can read this screen" after a
    /// rejected token, and every further tap spends another upload of the user's
    /// screen on a failure that is already known to repeat.
    ///
    /// Compared by identity against the constants above rather than by matching
    /// words in them, so this is two references to one literal rather than a
    /// parser. It should become a case on `ScreenReadOutcome` the next time that
    /// file is opened; this is what fits inside the schema as it stands.
    public static func describesSetup(_ detail: String) -> Bool {
        detail == notConfigured || detail == tokenRejected || detail == addressNotAServer
    }

    /// A sentence for the strip.
    ///
    /// **Four cases are answered here rather than by `AIEngineError.message`**,
    /// and the block above says why: that enum is shared with the text engine and
    /// three of its sentences describe a passage of text, a language, or a build
    /// with no cloud model — none of which exists on this path. Everything else
    /// falls through to the enum, where its wording is right for both.
    ///
    /// Internal rather than private so `ScreenReadServiceTests` can hold the four
    /// to the strings the user actually sees, which is the half that went wrong.
    static func explain(_ error: any Error) -> String {
        switch error {
        // 401/403 from `BackendTransport.mapped`. The address works; the token
        // does not. Naming the screen that owns the field is the whole difference
        // between this and a dead end.
        case AIEngineError.cloudNotConfigured:
            return tokenRejected
        // `mapped`'s default branch with a body it could not read an error out of
        // — a 404 being much the likeliest way to get here.
        case AIEngineError.failed(let detail) where detail.isEmpty:
            return addressNotAServer
        // 413 and 422. Both name an edit to a passage of text on a path whose
        // input is a JPEG of the screen.
        case AIEngineError.inputTooLong:
            return "The screen was too large for the screen reading server to accept."
        case AIEngineError.refused:
            return "The screen reading server declined to read this screen."
        case let error as AIEngineError:
            return error.message
        case ScreenReadError.needsFullAccess:
            return "Screen reading needs Full Access to reach the network."
        case ScreenReadError.noCloudReader:
            return Self.notConfigured
        case ScreenReadError.network(let detail):
            return detail.isEmpty ? "The screen reader could not be reached." : detail
        case ScreenReadError.failed(let detail):
            return detail.isEmpty ? "The screen could not be read." : detail
        default:
            return "The screen could not be read."
        }
    }
}
