import Foundation
import os

// MARK: - Why there is a channel here at all
//
// **The keyboard cannot record, and that is an OS boundary, not a permission.**
// Apple's "Configuring open access for a custom keyboard" lists "No access to
// microphone and speaker" under the keyboard sandbox, and enabling open access
// adds Location, Contacts, a shared container, network and iCloud — never the
// microphone. Developers who try it anyway get `AVAudioSession` error 561145187,
// `cannotStartRecording`, with Full Access granted and the microphone entitled.
//
// **So the microphone lives in the containing app, and this is the wire between
// them.** That is the architecture Wispr Flow ships on iOS — a "Flow Session"
// held open by their app while their keyboard is a reader — and it is the one
// this repo already runs for screen context: sensor in another process, result
// across the App Group, keyboard reads and never decides.
//
// **The session has to be started from the app, in the foreground, and that is
// the same 561145187.** An app in the background cannot *begin* recording; an
// app whose recording session is already active keeps it across a switch under
// the `audio` background mode. So the shape is forced: the user starts a session
// in aBitBetterKeyboard, switches to WhatsApp, and the keyboard's microphone button
// then opens and closes utterances inside a session that is already live. There
// is no supported way for a keyboard extension to launch its own app —
// `UIApplication` is unavailable to extensions and the responder-chain `openURL`
// workaround is explicitly disallowed — so nothing here pretends to have one.
// When no session is live the keyboard says so and says where to go.
//
// **Nothing in this channel is audio.** The recording lives in one buffer in the
// app, goes to the transcriber, and is released; what crosses is text, levels
// and counters. `ScreenReadingRecord` carries the same promise for pixels, and
// for the same reason: the shared container is backed up.

// MARK: - Where the channel lives

public enum DictationChannel {

    public static let statePageBytes = 192
    public static let requestPageBytes = 96

    public static var directoryURL: URL? {
        SharedContainer.url?.appendingPathComponent("dictation", isDirectory: true)
    }

    public static var stateURL: URL? { directoryURL?.appendingPathComponent("state.bin") }
    public static var requestURL: URL? { directoryURL?.appendingPathComponent("request.bin") }
    public static var transcriptURL: URL? {
        directoryURL?.appendingPathComponent("transcript.json")
    }
    public static var partialURL: URL? {
        directoryURL?.appendingPathComponent("partial.json")
    }

    /// False in the keyboard until the user grants Full Access, which is why
    /// dictation is a Full-Access feature end to end.
    public static var isReachable: Bool { SharedContainer.url != nil }

    static let log = Logger(subsystem: "com.nitai.aikeyboard", category: "DictationChannel")

    /// Zeroed in place rather than unlinked, for the reason `CaptureChannel.clear()`
    /// gives: another process may have these pages mapped, and unlinking a mapped
    /// file leaves it reading an inode nobody will write again.
    public static func clear() {
        guard prepareDirectory() != nil, let stateURL, let requestURL, let transcriptURL,
            let partialURL
        else {
            return
        }
        SharedPage<DictationState>(url: stateURL, bytes: statePageBytes, writable: true)?.reset()
        SharedPage<DictationRequest>(url: requestURL, bytes: requestPageBytes, writable: true)?
            .reset()
        try? FileManager.default.removeItem(at: transcriptURL)
        try? FileManager.default.removeItem(at: partialURL)
    }

    /// Removes a transcript or partial whose session is no longer running.
    ///
    /// The same obligation `CaptureChannel.discardReadingOfADeadSession` carries,
    /// and it is sharper here: a transcript is a sentence the user *dictated*,
    /// sitting in a container that is backed up — and a partial is exactly the
    /// same sentence, caught mid-utterance rather than at the end. The app
    /// deletes both when a session ends; this covers the ending the app never
    /// sees, which is the jetsam kill the whole heartbeat exists to detect.
    @discardableResult
    public static func discardTranscriptOfADeadSession(
        in directory: URL, now: UInt64 = CaptureClock.now()
    ) -> Bool {
        let transcript = directory.appendingPathComponent("transcript.json")
        let partial = directory.appendingPathComponent("partial.json")
        let hasTranscript = FileManager.default.fileExists(atPath: transcript.path)
        let hasPartial = FileManager.default.fileExists(atPath: partial.path)
        guard hasTranscript || hasPartial else { return false }

        let state = SharedPage<DictationState>(
            url: directory.appendingPathComponent("state.bin"),
            bytes: statePageBytes, writable: false)?.load()
        if let state, state.isAlive(now: now) { return false }

        var removedSomething = false
        if hasTranscript, (try? FileManager.default.removeItem(at: transcript)) != nil {
            removedSomething = true
        }
        if hasPartial, (try? FileManager.default.removeItem(at: partial)) != nil {
            removedSomething = true
        }
        return removedSomething
    }

    static func prepareDirectory(_ url: URL? = DictationChannel.directoryURL) -> URL? {
        guard let url else { return nil }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}

// MARK: - Error

public enum DictationChannelError: Error, LocalizedError {
    case sessionEnded

    public var errorDescription: String? {
        "the dictation session ended before the transcript could be published"
    }
}
