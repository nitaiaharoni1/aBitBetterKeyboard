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
/// Measured over all 30 images in `Bar/screen-context/` on 2026-08-08, at the
/// size and encoding the capture process actually sends (602x1310 JPEG q70, not
/// the full-size PNG every earlier reading here used): sender 30/30, keyboard
/// language 30/30, message text 18/30 exact and 25/30 within 90% of exact. Zero
/// of the 30 returned a chrome string from the bar's `traps` list, and zero
/// returned text the bar records as not being on screen. Median 4.9s, p90 5.7s,
/// 66 KB median on the wire.
///
/// Those are a reading with a date on it, not a property of the system: a repeat
/// run minutes later scored 29/30 sender and is committed beside it as
/// `cloud_outputs_repeat.json`, and the two disagree on 2 of 30 frames.
///
/// **Those four numbers were taken at the corpus's native 1206x2622, as a PNG,
/// and neither is what this type sends.** `read(_:)` encodes JPEG q0.70 and the
/// capture process halves the frame first. `Bar/screen-context/README.md`
/// §"Size and format" scores the 2x2 and settles it: 602x1310 JPEG is 74% fewer
/// bytes than the PNG above and no worse on any axis — sender 29-30/30,
/// keyboard language 30/30, message 18-19/30 exact and 25-26/30 within 90%, no
/// traps, over three runs at 66 KB median instead of 250 KB. It
/// also records that the line above is a *stored* reading, and that no dated
/// model version exists to pin it to: two runs of this exact configuration
/// minutes apart disagree on 2 of 30 and move sender by one — that pair is
/// committed as `cloud_outputs.json` and `cloud_outputs_repeat.json` — while runs
/// a day apart move far more. Re-measure both sides together, in one sitting.
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
                payload: .screenJPEG(jpeg)))

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
        //
        // **Matched against the whole catalogue, and matched raw.** The
        // identifiers in `KeyboardLanguage` are exactly the lowercase English
        // names the prompt asks for, so "hebrew" and "english" resolve to the two
        // languages they always resolved to, byte for byte, and "arabic" now
        // resolves too instead of being swept into the fallback. Nothing is
        // lowercased or trimmed on the way in, deliberately: any other spelling
        // reaches the script check exactly as it did before, which keeps every
        // answer this could give for an English or a Hebrew screen unchanged.
        // The fallback is where the widening actually bites, because it is
        // reached whether or not the model ever learns to say "arabic": it used
        // to answer `.english` for every script that was not Hebrew, which is how
        // an Arabic screen came back with "reply in English".
        let language =
            KeyboardLanguage(rawValue: fields["language"] ?? "")
            ?? .answering(LanguageDetector.scripts(in: message))

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

// ScreenPrompt is in ScreenPrompt.swift.
