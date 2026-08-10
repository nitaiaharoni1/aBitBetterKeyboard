import XCTest

@testable import AIKeyboardCore

// MARK: - A transport that answers what the test says

/// Stands in for the backend. It records what it was asked, answers with a
/// fixed set of fields or an error, and can be held open so a second request
/// arrives while the first is still running.
final class FakeTransport: CloudTransport, @unchecked Sendable {

    private let lock = NSLock()
    private var _calls = 0
    private var _requests: [CloudRequest] = []
    private let gate = Gate()

    let answer: [String: String]
    let failure: AIEngineError?
    /// When true, `send` waits for `release()` before answering.
    var holdOpen = false

    init(answer: [String: String] = [:], failure: AIEngineError? = nil) {
        self.answer = answer
        self.failure = failure
    }

    var calls: Int {
        lock.lock()
        defer { lock.unlock() }
        return _calls
    }

    var requests: [CloudRequest] {
        lock.lock()
        defer { lock.unlock() }
        return _requests
    }

    func send(_ request: CloudRequest) async throws -> [String: String] {
        lock.lock()
        _calls += 1
        _requests.append(request)
        lock.unlock()
        await gate.arrived()

        if holdOpen { await gate.wait() }
        if let failure { throw failure }
        return answer
    }

    /// Returns once `send` has been entered, so a test can be sure the read is
    /// genuinely in flight before it taps again.
    func waitUntilCalled() async throws { await gate.waitForArrival() }

    func release() async { await gate.open() }
}

/// Two one-shot signals, both directions. An actor rather than a semaphore
/// because the thing being coordinated is an `async` call and blocking a test
/// thread on one is how a test deadlocks the cooperative pool.
private actor Gate {
    private var isOpen = false
    private var hasArrived = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var watching: [CheckedContinuation<Void, Never>] = []

    func arrived() {
        hasArrived = true
        watching.forEach { $0.resume() }
        watching = []
    }

    func waitForArrival() async {
        guard !hasArrived else { return }
        await withCheckedContinuation { watching.append($0) }
    }

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiting.append($0) }
    }

    func open() {
        isOpen = true
        waiting.forEach { $0.resume() }
        waiting = []
    }
}
