import Foundation
import os

// MARK: - The keyboard end

/// The keyboard's end: it reads `state.bin` and the transcript, and owns
/// `request.bin`.
public final class DictationChannelReader: @unchecked Sendable {

    private let stateURL: URL
    private let transcriptURL: URL
    private let partialURL: URL
    private let directory: URL
    private let requestPage: SharedPage<DictationRequest>?
    private let statePage = OSAllocatedUnfairLock<SharedPage<DictationState>?>(initialState: nil)

    public convenience init?() {
        guard let directory = DictationChannel.prepareDirectory() else { return nil }
        self.init(directory: directory)
    }

    public init(directory: URL) {
        self.directory = directory
        self.stateURL = directory.appendingPathComponent("state.bin")
        self.transcriptURL = directory.appendingPathComponent("transcript.json")
        self.partialURL = directory.appendingPathComponent("partial.json")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.requestPage = SharedPage<DictationRequest>(
            url: directory.appendingPathComponent("request.bin"),
            bytes: DictationChannel.requestPageBytes, writable: true)
    }

    public func state() -> DictationState? {
        statePage.withLock { page in
            if page == nil {
                page = SharedPage<DictationState>(
                    url: stateURL, bytes: DictationChannel.statePageBytes, writable: false)
            }
            return page?.load()
        }
    }

    public func transcript() -> DictationTranscriptRecord? {
        guard let data = try? Data(contentsOf: transcriptURL) else { return nil }
        return try? JSONDecoder().decode(DictationTranscriptRecord.self, from: data)
    }

    public func partial() -> DictationPartialRecord? {
        guard let data = try? Data(contentsOf: partialURL) else { return nil }
        return try? JSONDecoder().decode(DictationPartialRecord.self, from: data)
    }

    @discardableResult
    public func discardTranscriptOfADeadSession(now: UInt64 = CaptureClock.now()) -> Bool {
        DictationChannel.discardTranscriptOfADeadSession(in: directory, now: now)
    }

    /// The dead-man's switch, refreshed on every poll while the panel is open.
    public func keepAlive(now: UInt64 = CaptureClock.now()) {
        requestPage?.mutate { $0.keyboardAliveAt = now }
    }

    /// Opens an utterance and returns its number. The transcript that answers
    /// this tap carries the number this returns; anything else answers an
    /// earlier one.
    @discardableResult
    public func beginUtterance(now: UInt64 = CaptureClock.now()) -> UInt64 {
        guard let requestPage else { return 0 }
        var opened: UInt64 = 0
        requestPage.mutate { request in
            request.utterance &+= 1
            request.startedAt = now
            request.keyboardAliveAt = now
            opened = request.utterance
        }
        return opened
    }

    public func stopUtterance(now: UInt64 = CaptureClock.now()) {
        requestPage?.mutate { request in
            request.stopUtterance = request.utterance
            request.stoppedAt = now
            request.keyboardAliveAt = now
        }
    }

    public func cancelUtterance(now: UInt64 = CaptureClock.now()) {
        requestPage?.mutate { request in
            request.cancelUtterance = request.utterance
            request.cancelledAt = now
            request.keyboardAliveAt = now
        }
    }

    public func request() -> DictationRequest? { requestPage?.load() }
}
