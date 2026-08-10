import AIKeyboardCore
import Foundation

extension DictationService {

    // MARK: The poll

    func startPolling() {
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func poll() {
        guard isRunning, let writer else { return }
        let now = CaptureClock.now()

        // 1 Hz, independent of everything else in this method. It is the only
        // signal that separates "this app is running" from "this app was
        // jetsammed with `phase` still saying listening".
        if CaptureClock.elapsed(since: lastHeartbeat, now: now) >= CaptureClock.nanoseconds(1) {
            writer.heartbeat(now: now)
            lastHeartbeat = now
        }

        if expiresAtMonotonic > 0, now >= expiresAtMonotonic {
            stop(.expired)
            return
        }

        // One read of the audio thread's state per poll, and the only one.
        let reading = recording.reading()
        level = reading.level
        writer.setLevel(reading.level)
        if reading.isFull, openUtterance > 0 {
            // Sixty seconds is somebody who has forgotten they are recording, so
            // it closes as if they had tapped Insert rather than discarding what
            // they said.
            Self.log.notice("utterance \(self.openUtterance) hit the length cap")
            close(utterance: openUtterance)
            return
        }

        guard let request = writer.request() else { return }

        // The dead-man's switch. A keyboard extension is killed rather than
        // dismissed all the time, and an utterance left open by one is a
        // microphone recording for nobody.
        if openUtterance > 0, !request.isKeyboardAlive(now: now) {
            Self.log.notice("dropping utterance \(self.openUtterance): the keyboard stopped answering")
            drop()
            return
        }

        if request.cancelUtterance >= openUtterance, openUtterance > 0 {
            drop()
            return
        }

        if request.utterance > openUtterance, request.wantsRecording(now: now) {
            open(utterance: request.utterance, at: now)
            return
        }

        if openUtterance > 0, request.stopUtterance >= openUtterance {
            close(utterance: openUtterance)
        }
    }

    private func open(utterance: UInt64, at now: UInt64) {
        recording.begin()
        openUtterance = utterance
        recordingStartedAt = now
        phase = .listening
        writer?.setPhase(.listening, utterance: utterance)
    }

    private func drop() {
        recording.discard()
        openUtterance = 0
        phase = .idle
        writer?.setPhase(.idle)
    }

    private func close(utterance: UInt64) {
        guard openUtterance == utterance, let writer else { return }
        openUtterance = 0
        phase = .transcribing
        writer.setPhase(.transcribing, utterance: utterance)
        writer.count(\.utterances)
        utterances += 1

        // One transaction, so the length, the verdict and the bytes cannot come
        // from three different moments while the tap is still delivering.
        let taken = recording.end()
        let seconds = taken.seconds
        let verdict = taken.verdict
        let recordedAt = recordingStartedAt
        // Stamped now, not when the answer comes back. See `publish`.
        let session = sessionID

        // **The gate runs before the upload, not after it.** Four seconds of
        // silence come back from the model as a fluent invented sentence — see
        // `SpeechGate` — so a recording with nothing in it must never reach the
        // network at all. It is also the cheaper order: no bytes, no call, no
        // wait.
        guard verdict.isSpeech else {
            writer.count(\.refusedNoSpeech)
            refusedNoSpeech += 1
            level = 0
            phase = .idle
            writer.setPhase(.idle)
            publish(
                DictationTranscriptRecord(
                    sessionID: session, utterance: utterance, outcome: .nothing, text: "",
                    detail: verdict.explanation, recordedAt: recordedAt,
                    completedAt: CaptureClock.now(), seconds: seconds))
            return
        }

        let audio = taken.audio
        level = 0
        let languages = SharedStore.shared.enabledLanguages

        // **Not cancelled, and the previous one is not either.** An earlier
        // version cancelled any in-flight transcription here, which is wrong in
        // the one case it matters: somebody dictating two sentences quickly would
        // have the first silently dropped, and the keyboard that asked for it
        // would wait for a record nobody was going to publish. Both run; the
        // records carry their own utterance numbers and the keyboard takes the
        // one it asked for.
        transcribing = Task { [weak self] in
            await self?.transcribe(
                audio: audio, session: session, utterance: utterance, seconds: seconds,
                recordedAt: recordedAt, languages: languages)
        }
    }

    private func transcribe(
        audio: Data, session: UUID, utterance: UInt64, seconds: Double, recordedAt: UInt64,
        languages: [KeyboardLanguage]
    ) async {
        inFlight += 1
        defer {
            inFlight -= 1
            if inFlight == 0 {
                phase = .idle
                writer?.setPhase(.idle)
            }
        }

        // `isReady` as well as `configured()`: a build ships a backend address, so
        // `configured()` alone is true on a fresh install and this would upload the
        // recording before finding out there is no token to send with it. Failing
        // here costs the user a message instead of their audio.
        guard BackendTransport.isReady(), let transport = BackendTransport.configured() else {
            fail(
                session: session, utterance: utterance, recordedAt: recordedAt, seconds: seconds,
                detail: AIEngineError.cloudNotConfigured.message)
            return
        }

        do {
            let output = try await CloudDictation(transport: transport)
                .transcribe(audio, languages: languages)
            guard !Task.isCancelled else { return }
            lastTranscript = output.value.text
            lastError = ""
            publish(
                DictationTranscriptRecord(
                    sessionID: session, utterance: utterance, outcome: .transcribed,
                    text: output.value.text, languages: output.value.languages,
                    recordedAt: recordedAt, completedAt: CaptureClock.now(), seconds: seconds))
        } catch {
            guard !Task.isCancelled else { return }
            let detail = (error as? AIEngineError)?.message ?? error.localizedDescription
            // `.empty` is what the transcriber throws when the model heard
            // nothing after all — the second layer behind `SpeechGate`, and it
            // reads to the user as "I didn't catch that", not as a failure.
            let outcome: DictationOutcome = (error as? AIEngineError) == .empty ? .nothing : .failed
            if outcome == .failed { writer?.count(\.failures) }
            fail(
                session: session, utterance: utterance, recordedAt: recordedAt, seconds: seconds,
                detail: detail, outcome: outcome)
        }
    }

    private func fail(
        session: UUID, utterance: UInt64, recordedAt: UInt64, seconds: Double, detail: String,
        outcome: DictationOutcome = .failed
    ) {
        lastError = detail
        publish(
            DictationTranscriptRecord(
                sessionID: session, utterance: utterance, outcome: outcome, text: "",
                detail: detail, recordedAt: recordedAt, completedAt: CaptureClock.now(),
                seconds: seconds))
    }

    /// Every path out of an utterance publishes something, including the ones
    /// that produced no text.
    ///
    /// **A request that produced nothing must not produce silence.** The
    /// keyboard is sitting on a spinner waiting for a record carrying its own
    /// number; a failure that says nothing is indistinguishable from an app that
    /// is no longer running, and the user is told the wrong thing about a
    /// microphone that is working. `ScreenReadingRecord` carries the same rule
    /// and it was learned there first.
    private func publish(_ record: DictationTranscriptRecord) {
        // **A transcription outlives the session it was recorded in, and the
        // window is real.** `stop()` cancels only the newest in-flight call, and
        // `DictationChannelWriter.publish` refuses only while the channel is
        // *ended* — so a user who stops a session and starts another one inside
        // the two-or-so seconds a transcription takes reopens that gate, and the
        // old answer lands in the new session carrying an utterance number the
        // new session may reach. That is a sentence from before, inserted into
        // whatever they are typing now. The session is stamped on the record at
        // the moment the recording closed, and compared here.
        guard record.sessionID == sessionID else {
            Self.log.notice("dropped a transcript belonging to a session that has ended")
            return
        }
        do {
            try writer?.publish(record)
        } catch {
            Self.log.notice("transcript dropped: \(error.localizedDescription, privacy: .public)")
        }
    }
}
