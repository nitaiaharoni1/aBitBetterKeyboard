import XCTest

@testable import AIKeyboardCore

/// A stand-in engine, so the router can be tested without a model or a network.
private struct StubEngine: TextIntelligence {
    var handles: (String) -> Bool = { _ in true }
    var answer: String = "ok"
    var failure: AIEngineError?
    /// Set by the test to prove which engine actually ran.
    let calls = Counter()

    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
        func increment() {
            lock.lock()
            value += 1
            lock.unlock()
        }
    }

    func canHandle(_ text: String, action: AIAction) -> Bool { handles(text) }

    func fix(_ text: String) async throws -> String {
        calls.increment()
        if let failure { throw failure }
        return answer
    }

    func variants(for text: String, tone: ToneStyle?) async throws -> [RewriteVariant] {
        calls.increment()
        if let failure { throw failure }
        return [RewriteVariant(tone: .clearer, text: answer)]
    }

    func replies(to context: ScreenContext) async throws -> [ReplyOption] {
        calls.increment()
        if let failure { throw failure }
        return [ReplyOption(intent: "Accept", icon: "checkmark", text: answer)]
    }
}

final class RoutedIntelligenceTests: XCTestCase {

    func testSupportedLanguageStaysOnDevice() async throws {
        let onDevice = StubEngine(answer: "on-device")
        let cloud = StubEngine(answer: "cloud")
        let router = RoutedIntelligence(onDevice: onDevice, cloud: cloud)

        let output = try await router.fix("the meeting is tomorrow")

        XCTAssertEqual(output.value, "on-device")
        XCTAssertEqual(output.provenance, .onDevice)
        XCTAssertEqual(cloud.calls.count, 0, "cloud must not be touched for a language on-device supports")
    }

    /// The Hebrew case. On-device declines the language, so the text goes to the
    /// cloud and never reaches a model that would answer it in English.
    func testUnsupportedLanguageGoesToCloud() async throws {
        let onDevice = StubEngine(handles: { _ in false }, answer: "on-device")
        let cloud = StubEngine(answer: "cloud")
        let router = RoutedIntelligence(onDevice: onDevice, cloud: cloud)

        let output = try await router.fix("אני יבדוק את זה")

        XCTAssertEqual(output.value, "cloud")
        XCTAssertEqual(output.provenance, .cloud)
        XCTAssertEqual(onDevice.calls.count, 0)
    }

    /// No API key ships in this build, so this is the path Hebrew actually takes
    /// today: on-device answers anyway, and the result is labelled for what it is.
    func testUnsupportedLanguageWithNoCloudFallsBackAsBestEffort() async throws {
        let onDevice = StubEngine(handles: { _ in false }, answer: "best effort")
        let router = RoutedIntelligence(onDevice: onDevice, cloud: nil)

        let output = try await router.fix("אני יבדוק את זה")

        XCTAssertEqual(output.value, "best effort")
        XCTAssertEqual(output.provenance, .onDeviceBestEffort)
        XCTAssertTrue(output.provenance.isBestEffort)
    }

    /// The simulator case: availability claims the model is there, generation fails.
    func testOnDeviceFailureFallsThroughToCloud() async throws {
        let onDevice = StubEngine(answer: "on-device", failure: .modelNotReady)
        let cloud = StubEngine(answer: "cloud")
        let router = RoutedIntelligence(onDevice: onDevice, cloud: cloud)

        let output = try await router.fix("the meeting is tomorrow")

        XCTAssertEqual(output.value, "cloud")
        XCTAssertEqual(output.provenance, .cloud)
        XCTAssertEqual(onDevice.calls.count, 1, "on-device is tried first and only then given up on")
    }

    /// A guardrail trip is a decision about the content, not a transport failure.
    /// Quietly shipping refused text off the device would be the wrong instinct.
    func testRefusalIsNotRetriedElsewhere() async {
        let onDevice = StubEngine(answer: "on-device", failure: .refused)
        let cloud = StubEngine(answer: "cloud")
        let router = RoutedIntelligence(onDevice: onDevice, cloud: cloud)

        do {
            _ = try await router.fix("יאללה סבבה, נדבר אח\"כ")
            XCTFail("expected the refusal to surface")
        } catch let error as AIEngineError {
            XCTAssertEqual(error, .refused)
            XCTAssertEqual(cloud.calls.count, 0)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    /// Context limits are per engine, not per message. The on-device model's
    /// window is small enough that Rewrite's six-field schema overflowed it on a
    /// one-line input, and the cloud model took the same input fine — so running
    /// out of room on one engine has to mean "ask the other one", not "give up".
    func testRunningOutOfContextTriesTheOtherEngine() async throws {
        let onDevice = StubEngine(answer: "on-device", failure: .inputTooLong)
        let cloud = StubEngine(answer: "cloud")
        let router = RoutedIntelligence(onDevice: onDevice, cloud: cloud)

        let output = try await router.fix("I dont think we should do it because its not make sense")

        XCTAssertEqual(output.value, "cloud")
        XCTAssertEqual(cloud.calls.count, 1)
    }

    /// The first failure is the informative one — "Apple Intelligence is off"
    /// tells the user something; the cloud's "no key" does not.
    func testFirstFailureIsTheOneReported() async {
        let onDevice = StubEngine(answer: "on-device", failure: .appleIntelligenceOff)
        let cloud = StubEngine(answer: "cloud", failure: .cloudNotConfigured)
        let router = RoutedIntelligence(onDevice: onDevice, cloud: cloud)

        do {
            _ = try await router.fix("the meeting is tomorrow")
            XCTFail("expected an error")
        } catch let error as AIEngineError {
            XCTAssertEqual(error, .appleIntelligenceOff)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testNoEngineAtAllReportsSomethingActionable() async {
        let router = RoutedIntelligence(onDevice: nil, cloud: nil)
        do {
            _ = try await router.fix("anything")
            XCTFail("expected an error")
        } catch let error as AIEngineError {
            XCTAssertEqual(error, .deviceNotSupported)
            XCTAssertFalse(error.message.isEmpty, "every error must give the user something to read")
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testEveryErrorCarriesATitleAndAMessage() {
        let all: [AIEngineError] = [
            .modelNotReady, .appleIntelligenceOff, .deviceNotSupported,
            .unsupportedLanguage(.hebrew), .refused, .inputTooLong, .needsFullAccess,
            .cloudNotConfigured, .network(""), .empty, .timedOut, .failed("")
        ]
        for error in all {
            XCTAssertFalse(error.title.isEmpty, "\(error) has no title")
            XCTAssertFalse(error.message.isEmpty, "\(error) has no message")
        }
    }

    func testHebrewIsNamedInItsUnsupportedLanguageMessage() {
        XCTAssertTrue(AIEngineError.unsupportedLanguage(.hebrew).message.contains("Hebrew"))
    }
}

// MARK: - On-device support

@available(iOS 26.0, macOS 26.0, *)
final class FoundationModelsEngineTests: XCTestCase {

    /// Reads the real `supportedLanguages` set. If Apple ever adds Hebrew this
    /// test starts failing, which is the correct signal to delete the fallback.
    func testHebrewIsNotSupportedOnDevice() throws {
        let engine = FoundationModelsEngine()
        XCTAssertFalse(engine.canHandle("אני יבדוק את זה", action: .fix))
        XCTAssertFalse(
            engine.canHandle("Can you check the deployment on staging, אני חושב שיש שם באג", action: .fix),
            "a mostly-Latin sentence with Hebrew in it is still Hebrew to this model"
        )
    }

    func testEnglishIsSupportedOnDevice() throws {
        XCTAssertTrue(FoundationModelsEngine().canHandle("the meeting is tomorrow", action: .fix))
    }

    /// Measured, not assumed: this model is good at Fix and Tone and bad at the
    /// two actions that require deciding something.
    func testRewriteAndReplyPreferTheCloudEvenInEnglish() throws {
        let engine = FoundationModelsEngine()
        XCTAssertFalse(engine.canHandle("i cant make the 9am standup tomorrow", action: .rewrite))
        XCTAssertFalse(engine.canHandle("Can you take the standup tomorrow?", action: .reply))
        XCTAssertTrue(engine.canHandle("i cant make the 9am standup tomorrow", action: .tone))
    }

    func testTextWithNoLettersIsAccepted() throws {
        XCTAssertTrue(FoundationModelsEngine().canHandle("123 😅", action: .fix))
    }
}

// MARK: - Deadline

/// An engine that never returns, standing in for the on-device call on a
/// simulator: it does not fail, it blocks, and the app is killed for it.
private struct HangingEngine: TextIntelligence {
    func canHandle(_ text: String, action: AIAction) -> Bool { true }
    func fix(_ text: String) async throws -> String {
        try await Task.sleep(for: .seconds(600))
        return ""
    }
    func variants(for text: String, tone: ToneStyle?) async throws -> [RewriteVariant] { [] }
    func replies(to context: ScreenContext) async throws -> [ReplyOption] { [] }
}

final class DeadlineTests: XCTestCase {

    func testAHangingEngineFailsInsteadOfHangingTheKeyboard() async {
        let router = RoutedIntelligence(
            onDevice: HangingEngine(), cloud: nil, deadline: .milliseconds(150))
        let start = Date()

        do {
            _ = try await router.fix("the meeting is tomorrow")
            XCTFail("expected the deadline to fire")
        } catch let error as AIEngineError {
            XCTAssertEqual(error, .timedOut)
            XCTAssertLessThan(
                Date().timeIntervalSince(start), 5, "the deadline must actually cut the call short")
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    /// A stalled on-device model should not take the cloud down with it.
    func testATimeoutFallsThroughToTheOtherEngine() async throws {
        let router = RoutedIntelligence(
            onDevice: HangingEngine(), cloud: StubEngine(answer: "cloud"), deadline: .milliseconds(150))

        let output = try await router.fix("the meeting is tomorrow")

        XCTAssertEqual(output.value, "cloud")
        XCTAssertEqual(output.provenance, .cloud)
    }
}
