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
