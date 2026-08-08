import Foundation

/// What a raised request turned into. Three answers, because "no reading" hides
/// two different things and the user needs to be told which.
///
/// A request that produced nothing is not allowed to produce *silence*: the
/// keyboard waits up to twelve seconds for a record carrying its own sequence,
/// so a read that fails without saying so is indistinguishable from a capture
/// process that is not there. Every outcome below ends that wait.
public enum ScreenReadOutcome: String, Codable, Sendable {
    /// `sender` and `message` carry a reading.
    case read
    /// The screen was read and holds nothing worth replying to — the newest
    /// incoming bubble is a voice note, an image or the user's own message.
    /// An answer, not a failure.
    case nothing
    /// No reading was taken. `detail` says why, in a sentence the strip can show.
    case failed
}

/// One reading, as it crosses the App Group.
///
/// **Text and hashes only, by construction.** There is no image field, no
/// thumbnail, no reduction and nothing that renders, and that is the product
/// promise rather than an implementation detail: one frame at a time lives in a
/// single buffer inside the capture process and is overwritten by the next, and
/// nothing on disk, in the shared container or in a backup ever contains a
/// picture of the user's screen. Adding a field to this struct that could be
/// turned back into pixels breaks that sentence, so do not.
///
/// The two hash-shaped fields are not exceptions. `frameIdentity` is a SHA-256
/// of a 32x64 greyscale reduction — a value that supports one question, *is this
/// the same screen*, and cannot be turned into an image or compared for
/// similarity — and it never leaves the device.
public struct ScreenReadingRecord: Codable, Equatable, Sendable {

    /// Which broadcast session produced this. A reading from a previous session
    /// is never offerable, however recent it looks.
    public let sessionID: UUID

    /// The `CaptureIntent.readNow` value that asked for it. The keyboard matches
    /// this against its own request so it can tell the answer to *this* tap from
    /// the answer to the last one.
    public let requestSequence: UInt64

    /// The fingerprint of the frame that was read. The freshness gate's only
    /// content-identity condition compares this against what the extension is
    /// seeing right now.
    public let frameIdentity: FrameIdentity

    /// `CaptureClock` nanoseconds. When the frame was sampled.
    public let capturedAt: UInt64

    /// `CaptureClock` nanoseconds. When the reading came back. Later than
    /// `capturedAt` by roughly the length of the read, and the field the
    /// confirmation condition is measured against.
    public let readAt: UInt64

    /// `AIProvenance` raw form: `onDevice`, `onDeviceBestEffort` or `cloud`.
    /// Carried as a string because this target must not import the engines.
    public let provenance: String

    /// What the request turned into. Defaulted to `.read` in the initialiser so
    /// that every caller building a reading says nothing about it, and only the
    /// two paths that produce no reading have to.
    public let outcome: ScreenReadOutcome

    /// Why there is no reading, in a sentence fit to show the user. Empty when
    /// `outcome` is `.read`.
    public let detail: String

    public let sender: String
    public let message: String

    /// `KeyboardLanguage.rawValue`. Which keyboard should open to answer this.
    ///
    /// A string rather than the enum, and it stays one now that
    /// `KeyboardLanguage` is in this target: this is a file format two processes
    /// parse, so a case added to the enum should widen the reader's default
    /// rather than fail the decode of every field beside it.
    /// `ScreenReadingRecord.keyboardLanguage` does the conversion.
    public let language: String

    public init(
        sessionID: UUID,
        requestSequence: UInt64,
        frameIdentity: FrameIdentity,
        capturedAt: UInt64,
        readAt: UInt64,
        provenance: String,
        outcome: ScreenReadOutcome = .read,
        detail: String = "",
        sender: String,
        message: String,
        language: String
    ) {
        self.sessionID = sessionID
        self.requestSequence = requestSequence
        self.frameIdentity = frameIdentity
        self.capturedAt = capturedAt
        self.readAt = readAt
        self.provenance = provenance
        self.outcome = outcome
        self.detail = detail
        self.sender = sender
        self.message = message
        self.language = language
    }

    /// What to show the user when this record ended their wait without a
    /// reading.
    ///
    /// `.nothing` is not a failure and must not read like one: the screen was
    /// read perfectly and had nothing on it worth answering. `.failed` carries a
    /// reason from the capture process, and falls back only when that process
    /// failed to say why.
    public var failureExplanation: String {
        switch outcome {
        case .read:
            return ""
        case .nothing:
            return "There is no message on this screen to reply to."
        case .failed:
            return detail.isEmpty ? "The screen could not be read." : detail
        }
    }
}
