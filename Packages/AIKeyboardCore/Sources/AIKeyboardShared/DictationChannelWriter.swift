import Foundation
import os

// MARK: - The recording end

/// The app's end: it owns `state.bin`, reads `request.bin`, and is the only
/// thing that ever writes a transcript.
public final class DictationChannelWriter: @unchecked Sendable {

    private let statePage: SharedPage<DictationState>
    private let requestURL: URL
    private let transcriptURL: URL
    private let requestPage = OSAllocatedUnfairLock<SharedPage<DictationRequest>?>(initialState: nil)
    private let hasEnded = OSAllocatedUnfairLock(initialState: false)

    public convenience init?() {
        guard let directory = DictationChannel.prepareDirectory() else { return nil }
        self.init(directory: directory)
    }

    /// Public for the reason `CaptureChannelWriter.init(directory:)` is:
    /// `AIKeyboardCoreTests` carries no App Group entitlement, so both ends are
    /// driven against a temporary directory there.
    public init?(directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard
            let page = SharedPage<DictationState>(
                url: directory.appendingPathComponent("state.bin"),
                bytes: DictationChannel.statePageBytes, writable: true)
        else { return nil }
        self.statePage = page
        self.requestURL = directory.appendingPathComponent("request.bin")
        self.transcriptURL = directory.appendingPathComponent("transcript.json")
    }

    @discardableResult
    public func begin(
        sessionID: UUID = UUID(), seconds: Double, microphoneAuthorized: Bool,
        now: UInt64 = CaptureClock.now()
    ) -> UUID {
        hasEnded.withLock { $0 = false }
        try? FileManager.default.removeItem(at: transcriptURL)
        statePage.reset()
        statePage.mutate { state in
            state.setSessionID(sessionID)
            state.startedAt = now
            state.heartbeatAt = now
            state.expiresAt = seconds > 0 ? now &+ CaptureClock.nanoseconds(seconds) : 0
            state.micAuthorizedRaw = microphoneAuthorized ? 1 : 0
            state.phaseRaw = DictationPhase.idle.rawValue
            state.endReasonRaw = DictationEndReason.notEnded.rawValue
        }
        return sessionID
    }

    public func heartbeat(now: UInt64 = CaptureClock.now()) {
        statePage.mutate { $0.heartbeatAt = now }
    }

    public func setPhase(_ phase: DictationPhase, utterance: UInt64 = 0) {
        statePage.mutate { state in
            state.phaseRaw = phase.rawValue
            if utterance > 0 { state.currentUtterance = utterance }
        }
    }

    /// Written from the audio tap, so it does exactly one seqlock write and
    /// returns. Nothing here allocates.
    public func setLevel(_ level: Double) {
        statePage.mutate { $0.setLevel(level) }
    }

    public func count(_ counter: WritableKeyPath<DictationState, UInt32>) {
        statePage.mutate { $0[keyPath: counter] &+= 1 }
    }

    public func end(_ reason: DictationEndReason, now: UInt64 = CaptureClock.now()) {
        hasEnded.withLock { $0 = true }
        statePage.mutate { state in
            state.endReasonRaw = reason.rawValue
            state.phaseRaw = DictationPhase.idle.rawValue
            state.levelPermille = 0
            state.heartbeatAt = now
        }
        try? FileManager.default.removeItem(at: transcriptURL)
    }

    public func state() -> DictationState? { statePage.load() }

    public func request() -> DictationRequest? {
        requestPage.withLock { page in
            if page == nil {
                page = SharedPage<DictationRequest>(
                    url: requestURL, bytes: DictationChannel.requestPageBytes, writable: false)
            }
            return page?.load()
        }
    }

    /// Publishes a transcript, atomically so the keyboard never reads half a JSON
    /// document.
    ///
    /// **Refused once the session has ended, and it deletes again afterwards** —
    /// the same two-sided check `CaptureChannelWriter.publish` makes, for the
    /// same reason: a transcription in flight when the user stopped the session
    /// lands after `end()` deleted the file, and a sentence somebody dictated
    /// would then sit in a backed-up container until the next launch.
    public func publish(_ record: DictationTranscriptRecord) throws {
        guard !hasEnded.withLock({ $0 }) else { throw DictationChannelError.sessionEnded }

        let data = try JSONEncoder().encode(record)
        try data.write(
            to: transcriptURL,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        statePage.mutate { $0.completedUtterance = record.utterance }

        if hasEnded.withLock({ $0 }) {
            try? FileManager.default.removeItem(at: transcriptURL)
            throw DictationChannelError.sessionEnded
        }
    }
}
