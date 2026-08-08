import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Reads a messaging screen with a multimodal cloud model.
///
/// This path exists for the same reason the cloud text path does: Apple's
/// on-device stack has no Hebrew. `VisionScreenReader` documents the OCR half of
/// that; this is the consequence. Every Hebrew screen in this product is read in
/// the cloud, and that is a product fact worth saying out loud rather than a
/// fallback — see `README.md`, because it means a Hebrew user's screen pixels
/// leave the device where an English user's do not.
///
/// Measured over all 30 images in `Bar/screen-context/`, three consecutive runs
/// agreeing exactly: sender 29/30, keyboard language 29/30, message text 19/30
/// exact and 26/30 within 90% of exact. Zero of the 30 returned a chrome string
/// from the bar's `traps` list, and zero returned text the bar records as not
/// being on screen. Median 5.3s, p90 6.4s.
///
/// **In `AIKeyboardShared` because the capture process is now a caller.** The
/// broadcast upload extension performs the read, and it must never link
/// `AIKeyboardCore`. One copy of the prompt and the parsing serves both it and
/// the in-app playground; two copies would drift from the numbers above.
public struct CloudScreenReader: ScreenReader {
    private let transport: any CloudTransport
    private let networkAllowed: @Sendable () -> Bool

    public init(
        transport: any CloudTransport,
        networkAllowed: @escaping @Sendable () -> Bool = { true }
    ) {
        self.transport = transport
        self.networkAllowed = networkAllowed
    }

    public func read(_ frame: CGImage) async throws -> AIOutput<ScreenReading?> {
        // Asked before the encode, not after: a keyboard without Full Access has
        // no network at all, and there is no point spending a JPEG on finding
        // that out.
        guard networkAllowed() else { throw ScreenReadError.needsFullAccess }
        guard let jpeg = Self.encode(frame) else {
            throw ScreenReadError.failed("The frame could not be encoded.")
        }
        return try await read(jpeg: jpeg)
    }

    /// The same read, given bytes that are already encoded.
    ///
    /// The capture process encodes on ReplayKit's delivery callback and reads on
    /// a serial queue, so the two halves happen on different threads and only
    /// the ~66 KB of JPEG crosses between them
    /// (`.claude/docs/screen-capture-design.md` §3.1). Splitting the encode out
    /// is what lets the pixels stop existing before the five-second network call
    /// starts: nothing here can reach a frame buffer.
    public func read(jpeg: Data) async throws -> AIOutput<ScreenReading?> {
        guard networkAllowed() else { throw ScreenReadError.needsFullAccess }

        let fields = try await transport.send(
            CloudRequest(
                instructions: ScreenPrompt.instructions,
                prompt: ScreenPrompt.task,
                fields: ScreenPrompt.fields,
                image: CloudImage(data: jpeg, mimeType: "image/jpeg")))

        return AIOutput(Self.parse(fields), provenance: .cloud)
    }

    // MARK: - Parsing

    static func parse(_ fields: [String: String]) -> ScreenReading? {
        let sender = (fields["sender"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let message = (fields["message"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        // Null for every field is the model's way of saying the screen holds
        // nothing to reply to — the newest incoming message was a voice note or
        // an image. That is an answer, so it is `nil` rather than an error.
        guard !message.isEmpty else { return nil }

        // The model's own language call is trusted over a fresh script check,
        // because it is answering the question the keyboard asks — which layout
        // opens to reply — and a Hebrew sentence carrying English loanwords
        // reads as majority-Latin to any character count.
        let language: KeyboardLanguage =
            switch fields["language"] {
            case "hebrew": .hebrew
            case "english": .english
            default: LanguageDetector.scripts(in: message).contains(.hebrew) ? .hebrew : .english
            }

        return ScreenReading(
            sender: sender,
            message: message,
            language: language,
            scripts: LanguageDetector.scripts(in: message))
    }

    /// JPEG at 70%. A screenshot is mostly flat colour, the model reads text off
    /// it rather than admiring it, and the frame is about to cross a mobile
    /// connection while the user waits.
    ///
    /// Public because the capture process encodes on ReplayKit's delivery
    /// callback rather than here, and it has to use the same quality this was
    /// scored at.
    public static func encode(_ frame: CGImage, quality: Double = 0.7) -> Data? {
        let buffer = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                buffer, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(
            destination, frame,
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return buffer as Data
    }
}

// MARK: - Prompt

/// The screen-reading prompt, kept beside the engine and versioned with it
/// because every line of it was bought with a measurement.
///
/// Two things here are load-bearing and look like style if you do not know the
/// history:
///
/// 1. **`messages` is a list, and it comes first.** Every wrong answer measured
///    on the bar was the model picking a bubble one to four positions above the
///    newest, not misreading pixels. Forcing it to enumerate every bubble before
///    naming one turns "which is newest" from a judgement into an index, and
///    took sender accuracy from 21/30 to 29/30.
/// 2. **`script` and `language` are separate questions.** Collapsing them scored
///    22/30; separating them scored 29/30. A Hebrew sentence borrowing English
///    words is *mixed* on screen and *Hebrew* to answer, and the keyboard needs
///    the second answer.
///
/// Two rules were tried and measured *worse*, so they are deliberately absent:
/// a paragraph explaining bubble tint and edge (cost 4 points and made repeat
/// runs disagree), and "a printed name always means the message is incoming"
/// (gained 1 point of message accuracy, lost 3 of sender).
enum ScreenPrompt {

    static let instructions = """
        You are looking at a screenshot of a phone messaging app.

        STEP 1. List EVERY message bubble on screen, top to bottom, in `messages`.
        Include bubbles that carry no text of their own: voice notes, images,
        stickers, files, call notices. Include the last bubble even if it is only
        partly visible.

        Do NOT list app chrome as a message: status bar, navigation bar, contact
        name, "online"/"typing…", date dividers, unread dividers, encryption
        notices, reaction or tapback pills, the text input placeholder, and
        bubble timestamps.
        A reply bubble that quotes an earlier message is ONE entry. Its text is
        ONLY the new text below the quote. The quoted part is a copy of something
        already said, set off by an accent bar, a tint, or a smaller font, and it
        must not appear in the entry's text at all.

        STEP 2. Take the LAST entry in your list whose from is "them". That one,
        and only that one, is the answer.

          - If its kind is "text", report its sender and text. `sender` must be a
            name: in a one-to-one chat that is the contact name from the
            navigation bar, never blank.
          - If its kind is anything else, there is nothing to reply to: return
            null for sender, message, script and language. Do NOT fall back to an
            earlier text message. The owner has already moved past it, so
            answering it would be stale.
          - If no entry has from "them", return null as well.

        Never pick an earlier message because it reads as more answerable. The
        last one is the answer even when it is a statement and an earlier one is
        a question.

        Transcription rules for the reported message:
          - Copy it exactly. Do not translate, correct, or re-spell anything.
          - A time or number inside the text is part of the text. Only the
            timestamp attached to the bubble is chrome.
          - An @mention at the start is part of the text, not a sender label.
          - Emoji inside the message body stay. A reaction pill hanging off the
            bubble corner is not part of it.
          - In a right-to-left message, report logical reading order: a full stop
            or comma rendered at the left edge of a line closes the sentence
            before it, so it belongs at the END of that sentence.
        """

    static let task = "Read the screenshot and report the newest message worth replying to."

    /// Order matters and is not alphabetical: enumerate, then transcribe, then
    /// classify. Every later field is decided with the list already written.
    static let fields: [CloudField] = [
        CloudField(
            "messages",
            "Every message bubble on screen, top to bottom.",
            items: [
                CloudField(
                    "from",
                    "\"them\" if someone else sent it, \"me\" if the phone's owner did. The owner's messages are usually aligned to the opposite side from everyone else's and often carry read receipts (checkmarks)."
                ),
                CloudField(
                    "kind",
                    "One of text, voice, image, sticker, file, system. \"text\" only if the bubble's own content is words you can read. A voice note is \"voice\" even though a duration is printed on it. An image with a caption under it is \"image\"; the caption is its own \"text\" entry."
                ),
                CloudField(
                    "sender",
                    "Who sent that bubble, by name. A group chat prints a name above each incoming bubble: use it. A one-to-one chat prints no name at all, because the contact's name sits in the navigation bar at the top of the screen: use that instead. Never leave this empty for a bubble from \"them\"."
                ),
                CloudField(
                    "text",
                    "The words in the bubble, exactly as written, wrapped lines joined with a single space. null when kind is not \"text\"."
                )
            ]),
        CloudField("sender", "The sender of the chosen message, or null."),
        CloudField("message", "The text of the chosen message, or null."),
        CloudField(
            "script",
            "What is physically on screen: \"hebrew\" for Hebrew letters, \"latin\" for Latin letters, \"mixed\" when it genuinely contains both, which includes a Hebrew sentence with English words embedded in it. Null when there is no message."
        ),
        CloudField(
            "language",
            "A different question: which keyboard opens to reply. A Hebrew sentence that borrows English words is answered in Hebrew, so its language is \"hebrew\" while its script is \"mixed\". Only a message actually written in English gets \"english\". Null when there is no message."
        )
    ]
}
