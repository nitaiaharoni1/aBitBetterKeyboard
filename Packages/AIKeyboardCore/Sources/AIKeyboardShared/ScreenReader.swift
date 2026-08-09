import CoreGraphics
import Foundation

// MARK: - Result

/// What one frame of a messaging screen turned out to say.
///
/// `nil` from a reader is a real answer, not a failure: a screen whose newest
/// incoming message is a voice note has nothing to reply to, and offering a
/// reply to the text above it would answer something the user already answered.
public struct ScreenReading: Sendable, Equatable {
    /// Who sent the newest incoming message. Wrong here is worse than a clumsy
    /// reply, because the reply gets addressed to the wrong person.
    public let sender: String
    public let message: String
    /// Which keyboard should open to answer this. A Hebrew sentence carrying
    /// English words is answered in Hebrew, so this is `.hebrew` while `script`
    /// is `.other`-free but mixed — the two questions have different answers.
    public let language: KeyboardLanguage
    /// What is physically on the screen, kept separate from `language` because
    /// the code-switching this product exists for makes them disagree.
    public let scripts: Set<TextScript>

    public init(
        sender: String,
        message: String,
        language: KeyboardLanguage,
        scripts: Set<TextScript>
    ) {
        self.sender = sender
        self.message = message
        self.language = language
        self.scripts = scripts
    }
}

// MARK: - Which keyboard answers

extension KeyboardLanguage {

    /// The keyboard to open in reply to a message written in these scripts.
    ///
    /// Here rather than in the catalogue because it is the readers' rule and both
    /// of them need it: `CloudScreenReader` falls back on it when the model names
    /// no language, and `VisionScreenReader` has nothing else to go on at all.
    /// It sits beside `ScreenReading.language`, whose doc comment is where the
    /// language/script distinction is written down.
    ///
    /// **Latin is deliberately not evidence.** Twelve of the fourteen keyboards
    /// this build draws are Latin-script, and no character count can tell French
    /// from English, so a Latin message answers in English exactly as it always
    /// has. Everything else is decided by the first catalogue entry whose script
    /// the message actually uses — and the catalogue's order is doing real work
    /// there: English and Hebrew lead it, which is why this returns the same two
    /// answers it used to for every message made of those two scripts. Below
    /// them it is alphabetical, so Cyrillic reads as Russian rather than
    /// Ukrainian and the Arabic script reads as Arabic rather than Persian. That
    /// is a tie-break, not a reading: the two pairs share almost their whole
    /// layout, and where the cloud model names a language its answer is taken
    /// over this.
    public static func answering(_ scripts: Set<TextScript>) -> KeyboardLanguage {
        allCases.first { $0.script != .latin && scripts.contains($0.script) } ?? .english
    }
}

// MARK: - Reader

/// Turns a captured frame into the one message worth replying to.
///
/// Split from the capture layer on purpose. Which API delivered the pixels —
/// ReplayKit today, ScreenCaptureKit once the deployment target allows it — has
/// no bearing on how they are read, and the reading is the half that carries a
/// measured score against `Bar/screen-context/`.
public protocol ScreenReader: Sendable {
    func read(_ frame: CGImage) async throws -> AIOutput<ScreenReading?>
}

// MARK: - Errors

public enum ScreenReadError: Error, Equatable, Sendable {
    /// The on-device recogniser could not read enough of the screen to be
    /// trusted with it. Not a failure to show the user: the router's cue to go
    /// to the cloud.
    case notReadableOnDevice
    case noCloudReader
    case needsFullAccess
    case network(String)
    case failed(String)
}
