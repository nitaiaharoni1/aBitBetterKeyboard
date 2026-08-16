import Foundation

/// Turns a recording into text with a multimodal cloud model.
///
/// **Cloud is not a fallback here, it is the only engine, and that is measured
/// rather than assumed.** Apple's `SpeechTranscriber` — the iOS 26 API, the one
/// `plan.md` §6 wanted — lists 30 locales and none of them is Hebrew;
/// `SFSpeechRecognizer`, which does list `he-IL`, reports
/// `supportsOnDeviceRecognition == false` for it, so even that path is a network
/// call. A keyboard whose reason to exist is Hebrew with English inside it
/// cannot be built on an engine that has neither. `Bar/dictation/README.md`
/// carries both readings.
///
/// **What it scores, on `Bar/dictation/`'s 36 clips, 2026-08-09.** Word error
/// rate 10.7% Hebrew, 8.5% English, 23.5% code-switched, 14.2% overall, with
/// 38/60 named entities recovered and 25/36 of the English words inside Hebrew
/// sentences kept in Latin letters. That last number is the one to watch: an
/// engine that writes `סינק` for `sync` has a respectable word error rate
/// against a transliterating reference and is useless in this product.
///
/// **Those read 10.1 / 8.0 / 17.7 / 11.9, 41/60 and 27/36 until 2026-08-16, and
/// no committed run produces them.** `harness/score.py` over every committed
/// outputs file reproduces `Bar/dictation/README.md` exactly. That set and the
/// scorer were committed together in `d023520f`, so it predates the scoring rule
/// that ships. Score the corpus before quoting it; do not restore from git.
///
/// Read those with the corpus's own warning attached: every clip is macOS `say`
/// output, so they are an optimistic ceiling and not a prediction of what a
/// person in a car will get. The corpus also fights the transcript on numbers —
/// its references spell them out, the prompt asks for digits, and `ten thirty`
/// coming back as `10:30` is scored as two errors while being the behaviour a
/// keyboard wants.
///
/// **The prompt shape is measured, one variant at a time, all in one sitting,
/// and both sides are committed under `Bar/dictation/ablation/`.** Baseline is
/// `speech`/`languages`/`text` in that order with no language hint and no
/// loanword rule: 15.6% overall, 31/60 entities, 18/36 Latin kept.
///
///   - **A hard loanword rule with examples** (`loanwords`) is the real win: 1.3
///     points of word error rate, five entities and six of the 36 Latin-script
///     words on its own, taking code-switched WER from 28.8% to 23.1%.
///   - **Naming the user's own keyboards** (`hint`) is worth nothing on this
///     corpus — 16.3% against the 15.6% baseline, which is slightly *worse* —
///     and ships anyway, because it earns its place on `multilingual/`, where
///     without it the Polish clip comes back as Portuguese.
///   - **Together**: 14.2% overall, 38/60 entities, 25/36 Latin kept. Better
///     than either alone on the overall and on both counts, and it does *not*
///     improve every axis — against the baseline, Hebrew-only WER goes 10.0% to
///     10.7% and English-only 8.0% to 8.5%, and loanwords alone is fractionally
///     ahead on code-switched WER. The trade is taken on the axis this product
///     is for.
///
/// Unlike the text and screen-context bars, this one is deterministic: two full
/// runs of the identical configuration came back byte for byte identical, so a
/// single-run delta here is evidence. That is a property of `temperature: 0`
/// over a fixed file, and it does not transfer to the other two bars.
///
/// **The one thing the prompt cannot do is refuse silence.** Four seconds of
/// digital silence come back as `speech: yes` and an invented sentence, in every
/// variant measured, and the best-scoring variant invents one out of stationary
/// noise as well. That is why `SpeechGate` decides on the device, before this
/// type is reached, and why nothing here treats the `speech` field as the
/// safeguard it looks like.
public struct CloudDictation: Sendable {

    private let transport: any CloudTransport
    private let networkAllowed: @Sendable () -> Bool

    public init(
        transport: any CloudTransport,
        networkAllowed: @escaping @Sendable () -> Bool = { true }
    ) {
        self.transport = transport
        self.networkAllowed = networkAllowed
    }

    public struct Transcription: Equatable, Sendable {
        public let text: String
        /// What the model reported hearing, comma-separated BCP-47.
        public let languages: String
        /// The model's own answer to "was anybody talking". Kept for the record
        /// and never trusted on its own; see the note above.
        public let heardSpeech: Bool

        public init(text: String, languages: String, heardSpeech: Bool) {
            self.text = text
            self.languages = languages
            self.heardSpeech = heardSpeech
        }
    }

    /// `languages` is the user's enabled keyboards. Empty is allowed and drops
    /// the hint, which is the baseline configuration above.
    public func transcribe(
        _ audio: Data, mimeType: String = "audio/wav", languages: [KeyboardLanguage] = []
    ) async throws -> AIOutput<Transcription> {
        guard networkAllowed() else { throw AIEngineError.needsFullAccess }

        let request = CloudRequest(
            instructions: DictationPrompt.instructions,
            prompt: DictationPrompt.prompt(for: languages),
            fields: DictationPrompt.fields,
            audio: CloudAudio(data: audio, mimeType: mimeType))

        let answer = try await transport.send(request)
        let text = (answer["text"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let heardSpeech = (answer["speech"] ?? "").lowercased() == "yes"

        // Both halves of "nothing was said" collapse to the same failure: the
        // model saying no, and the model saying yes and then writing nothing.
        // The second is not hypothetical — a schema the model must fill will be
        // filled — and an empty insertion reads to the user as a keyboard that
        // silently did nothing.
        guard heardSpeech, !text.isEmpty else { throw AIEngineError.empty }

        return AIOutput(
            Transcription(
                text: text, languages: (answer["languages"] ?? "").lowercased(),
                heardSpeech: heardSpeech),
            provenance: .cloud)
    }
}

// DictationPrompt is in DictationPrompt.swift.
