import Foundation

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

    public let sender: String
    public let message: String

    /// `KeyboardLanguage.rawValue`. Which keyboard should open to answer this.
    ///
    /// A string rather than the enum because `KeyboardLanguage` still lives in
    /// `AIKeyboardCore`, which imports SwiftUI and must never be linked into the
    /// broadcast extension. `ScreenReadingRecord.keyboardLanguage` in that target
    /// does the conversion.
    public let language: String

    public init(
        sessionID: UUID,
        requestSequence: UInt64,
        frameIdentity: FrameIdentity,
        capturedAt: UInt64,
        readAt: UInt64,
        provenance: String,
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
        self.sender = sender
        self.message = message
        self.language = language
    }
}
