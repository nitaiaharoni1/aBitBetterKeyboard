import AIKeyboardCore
import AVFoundation
import Foundation
import Speech
import os

/// Apple's own dictation model, transcribing the open utterance as it is spoken.
///
/// **This replaces re-uploading the whole recording every two seconds, and the
/// reason it exists is a measurement rather than a preference.** The streaming
/// half used to be `DictationService+Polling.maybeStartPartial`: every couple of
/// seconds it encoded *all* the audio so far and sent it to Vertex again, so a
/// sixty-second dictation made fifteen calls carrying about six times the audio
/// of the one call at the end — and, because `thinkingBudget` is paid per call,
/// roughly ten times the cost. It also got slower the longer somebody talked,
/// since each partial had more to upload than the last.
///
/// **The thing that made this possible is a locale list nobody here had checked.**
/// `.claude/rules/dictation.md` records that Apple's on-device stack has no Hebrew
/// in three places, and warns in the same breath not to reason from that to a
/// fourth API without checking it. `DictationTranscriber` is that fourth API. On
/// an iOS 26.2 simulator it reports 43 supported locales **including `he-IL`**,
/// `AssetInventory` reports that locale as `.supported` with a real installation
/// request behind it, and `SpeechTranscriber` — the one the rules file measured —
/// reports **zero** locales there, so the original reading proves nothing either
/// way and is worth redoing on a device.
///
/// **What this is not.** It is not the transcriber of record. `CloudDictation`
/// still produces the text that lands when the user stops, because that is the
/// engine with a measured number on the thing this product cannot regress:
/// English loanwords kept in Latin script inside Hebrew speech (25/36 on
/// `Bar/dictation/`). Whether Apple's Hebrew model writes `sync` or `סינק` is
/// **unmeasured, and no vendor publishes it for any engine** — plain word error
/// rate cannot even see the difference, which is why the research literature had
/// to invent a separate metric for it. So every reading from here is a draft that
/// the final transcript overwrites, and the worst case is that the user watches
/// Hebrew letters snap to Latin when they stop speaking.
///
/// Nothing here reaches the network and nothing leaves the device.
@available(iOS 26.0, *)
final class LiveTranscriber: @unchecked Sendable {

    /// Called on the main actor with the whole utterance as currently understood,
    /// never with a fragment to append. That is the same contract the keyboard
    /// already streams under — see `KeyboardController.replaceStreamedDictation`.
    private let onReading: @MainActor (String) -> Void

    private var analyzer: SpeechAnalyzer?
    private var transcriber: DictationTranscriber?
    private var results: Task<Void, Never>?

    /// Everything the analyzer has committed to. Volatile results replace one
    /// another; finalized ones accumulate.
    private var finalized = AttributedString()

    /// **Touched by the audio tap thread and by setup, so both are behind the
    /// lock.** `AVAudioConverter` is not safe to use from two threads, and the
    /// continuation must not be yielded into after it is finished.
    private let lock = OSAllocatedUnfairLock()
    private var converter: AVAudioConverter?
    private var analyzerFormat: AVAudioFormat?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?

    private static let log = Logger(subsystem: "com.nitai.aikeyboard", category: "Dictation")

    init(onReading: @escaping @MainActor (String) -> Void) {
        self.onReading = onReading
    }

    // MARK: Availability

    /// The locale Apple can transcribe for this keyboard language, or nil.
    ///
    /// `supportedLocale(equivalentTo:)` rather than a search of `supportedLocales`,
    /// because the keyboard's idea of a language is a bare code (`he`) and Apple's
    /// is a region-qualified one (`he-IL`); matching those by string is how a
    /// language that *is* supported gets reported as missing.
    static func supportedLocale(for language: KeyboardLanguage) async -> Locale? {
        await DictationTranscriber.supportedLocale(
            equivalentTo: Locale(identifier: language.languageTag))
    }

    /// Downloads the model for a locale if it is supported and not yet installed.
    ///
    /// **Called when a *session* opens, not when an utterance does.** It is a
    /// download; making the first tap on the microphone wait for one would be the
    /// spinner this whole feature exists to remove. An utterance that opens before
    /// it finishes simply does not stream, and the transcript still lands.
    ///
    /// `reserve` is what stops iOS reclaiming the asset. There is room for
    /// `AssetInventory.maximumReservedLocales` of them, which is 5 — so this is a
    /// per-language cost and not something to call for all 64.
    static func prepare(locale: Locale) async {
        let module = DictationTranscriber(locale: locale, preset: .progressiveLongDictation)
        let status = await AssetInventory.status(forModules: [module])
        guard status != .installed else { return }
        do {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
                try await request.downloadAndInstall()
            }
            _ = try await AssetInventory.reserve(locale: locale)
            Self.log.notice(
                "dictation-live installed \(locale.identifier(.bcp47), privacy: .public)")
        } catch {
            // Not a failure worth reporting to the user: the recording still works
            // and still produces a transcript at the end. All that is lost is the
            // words appearing while they speak.
            Self.log.notice(
                "dictation-live could not install \(locale.identifier(.bcp47), privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    // MARK: The utterance

    /// Opens a transcription for one utterance. Throws only where the caller can
    /// do nothing about it, and the caller treats that as "no streaming".
    func start(locale: Locale) async throws {
        let transcriber = DictationTranscriber(locale: locale, preset: .progressiveLongDictation)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        lock.withLock {
            self.analyzerFormat = format
            self.continuation = continuation
        }
        self.transcriber = transcriber
        self.analyzer = analyzer

        results = Task { [weak self] in await self?.consume(transcriber) }
        try await analyzer.start(inputSequence: stream)
    }

    /// **Volatile results replace, finalized results accumulate**, which is the
    /// whole of how a growing sentence is assembled. A build that appended both
    /// would show every word twice, and it would look exactly like a build that
    /// worked until somebody spoke a long sentence.
    private func consume(_ transcriber: DictationTranscriber) async {
        do {
            for try await result in transcriber.results {
                if result.isFinal {
                    finalized += result.text
                    await publish(String(finalized.characters))
                } else {
                    await publish(String(finalized.characters) + String(result.text.characters))
                }
            }
        } catch {
            Self.log.notice(
                "dictation-live stopped: \(error.localizedDescription, privacy: .public)")
        }
    }

    @MainActor
    private func publish(_ text: String) {
        onReading(text)
    }

    /// Called on the audio tap thread, once per buffer, for the length of the
    /// recording. It converts and hands over; it must not allocate more than that
    /// and must never wait on anything.
    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard let continuation, let format = analyzerFormat else { return }

        // Built on the first buffer rather than at `start`, because the analyzer's
        // preferred format is only known after it is asked, and the tap's own
        // format is only known here.
        if converter == nil || converter?.outputFormat != format {
            converter = AVAudioConverter(from: buffer.format, to: format)
        }
        guard let converter else { return }
        // Same shape as the recording tap's conversion in `DictationService+Engine`,
        // and the same reason for the headroom: a resample does not divide evenly.
        let capacity =
            AVAudioFrameCount(
                Double(buffer.frameLength) * format.sampleRate / buffer.format.sampleRate) + 1024
        guard let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            return
        }

        var supplied = false
        var error: NSError?
        converter.convert(to: converted, error: &error) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, converted.frameLength > 0 else { return }
        continuation.yield(AnalyzerInput(buffer: converted))
    }

    /// Ends the utterance and lets the analyzer finish what it has.
    ///
    /// The last words it produces are still only a draft — `close(utterance:)`
    /// sends the whole recording to `CloudDictation` in the same breath, and that
    /// answer replaces this one.
    func finish() async {
        lock.withLock {
            continuation?.finish()
            continuation = nil
            converter = nil
        }
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        results?.cancel()
        results = nil
        analyzer = nil
        transcriber = nil
        finalized = AttributedString()
    }

    /// Drops the utterance without waiting for anything, for the paths that are
    /// throwing the recording away rather than finishing it.
    func cancel() {
        lock.withLock {
            continuation?.finish()
            continuation = nil
            converter = nil
        }
        results?.cancel()
        results = nil
        let analyzer = self.analyzer
        self.analyzer = nil
        transcriber = nil
        finalized = AttributedString()
        Task { await analyzer?.cancelAndFinishNow() }
    }
}
