import XCTest

@testable import AIKeyboardCore
@testable import AIKeyboardShared

/// Covers how `BackendTransport` builds its request and reads the reply. The
/// HTTP call itself is not exercised here: no backend exists yet, and the app
/// deliberately holds no provider credential of its own.
final class BackendTransportTests: XCTestCase {

    func testDecodesTheFieldsObject() throws {
        let body = #"{"fields": {"text": "I don't think so."}}"#
        XCTAssertEqual(try BackendTransport.decode(Data(body.utf8))["text"], "I don't think so.")
    }

    /// A provider safety block has to read as a decision about the text, not as
    /// the service being down, so the backend flags it and the app says so.
    func testAnExplicitRefusalIsSurfacedAsARefusal() {
        let body = #"{"refused": true}"#
        XCTAssertThrowsError(try BackendTransport.decode(Data(body.utf8))) { error in
            XCTAssertEqual(error as? AIEngineError, .refused)
        }
    }

    func testAReplyWithNoFieldsIsReportedAsEmpty() {
        XCTAssertThrowsError(try BackendTransport.decode(Data("{}".utf8))) { error in
            XCTAssertEqual(error as? AIEngineError, .empty)
        }
    }

    func testUnreadableBodyIsReportedRatherThanCrashing() {
        XCTAssertThrowsError(try BackendTransport.decode(Data("not json".utf8)))
    }

    func testStatusCodesMapToActionableErrors() {
        let empty = Data("{}".utf8)
        XCTAssertEqual(BackendTransport.mapped(status: 401, body: empty), .cloudNotConfigured)
        XCTAssertEqual(BackendTransport.mapped(status: 422, body: empty), .refused)
        XCTAssertEqual(BackendTransport.mapped(status: 413, body: empty), .inputTooLong)
        if case .network = BackendTransport.mapped(status: 503, body: empty) {
        } else {
            XCTFail("a 5xx should read as the service being unreachable")
        }
    }

    /// **The two states that used to mean "no cloud" now mean "the built-in one",
    /// and that swap is the whole fix.**
    ///
    /// An absent or empty `cloudBackendURL` is what every stock install had, and
    /// before 2026-08-10 it answered nil. Nil is not a cosmetic result: it is why
    /// Hebrew Fix, Rewrite, Tone and Reply had no engine for the life of the
    /// install, and why the best-effort branch could not rescue them either, since
    /// Apple's on-device model rejects a session whose instructions are Hebrew.
    ///
    /// This asserts the opposite of what the shipped-and-broken build returned, so
    /// it fails against it rather than passing for the wrong reason.
    func testAnAbsentOrEmptyURLFallsBackToTheBundledBackend() {
        let suiteName = "BackendTransportFallbackTests"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.removePersistentDomain(forName: suiteName)

        XCTAssertNotNil(
            BackendTransport.configured(defaults: defaults),
            "a stock install stores nothing, and has to reach the shipped backend")
        // Named exactly, not just "something came back". `configured()` hides its
        // `baseURL`, so without this the test would pass against a fallback that
        // resolved to any URL at all.
        XCTAssertEqual(
            BackendTransport.effectiveURL(defaults: defaults), BackendTransport.bundledDefaultURL)
        XCTAssertTrue(BackendTransport.usesBundledBackend(defaults: defaults))

        // Whitespace is the same state as empty: `CloudModelView` trims before it
        // saves, so a field holding spaces is a field the user cleared.
        for blank in ["", "   ", "\n"] {
            defaults.set(blank, forKey: "cloudBackendURL")
            XCTAssertNotNil(
                BackendTransport.configured(defaults: defaults),
                "clearing the field puts the shipped backend back, it does not switch AI off")
        }

        // A backend the user typed still wins over the one that ships.
        defaults.set("https://api.example.com", forKey: "cloudBackendURL")
        XCTAssertNotNil(BackendTransport.configured(defaults: defaults))
        XCTAssertEqual(BackendTransport.effectiveURL(defaults: defaults), "https://api.example.com")
        XCTAssertFalse(BackendTransport.usesBundledBackend(defaults: defaults))

        // And a stored value that is not a web address is still no backend at all.
        // This is the one route to nil left, and `CloudModelView` refuses to save
        // it in the first place.
        defaults.set("not a url", forKey: "cloudBackendURL")
        XCTAssertNil(BackendTransport.configured(defaults: defaults))
    }

    /// **"There is somewhere to send" is not "the cloud works", and shipping a URL
    /// is what forced them apart.**
    ///
    /// Every screen that renders a cloud claim reads `isReady`: Settings' "Set
    /// up" row, the onboarding step in `SetupState`, the dictation screen's cloud
    /// card, the Screen Context prompt, and `ScreenReadService.canRead`, which is
    /// what lets a broadcast live. `configured()` is true from the first launch
    /// now, so had they kept reading it, a fresh install would tick off a
    /// completed setup and start recording somebody's screen for a keyboard that
    /// 401s on every call.
    func testReadinessNeedsATokenForTheShippedBackendButNotForYourOwn() {
        let suiteName = "BackendTransportReadinessTests"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.removePersistentDomain(forName: suiteName)

        // A fresh install: the shipped address is in force and no token has been
        // pasted in. There is somewhere to send and nothing that would be accepted.
        XCTAssertNotNil(BackendTransport.configured(defaults: defaults))
        XCTAssertFalse(
            BackendTransport.isReady(defaults: defaults),
            "the shipped backend gates on a bearer, so no token is an unfinished setup")

        defaults.set("   ", forKey: "cloudBackendToken")
        XCTAssertFalse(
            BackendTransport.isReady(defaults: defaults),
            "whitespace is not a token — it is dropped before the header is built")

        defaults.set("s3cret", forKey: "cloudBackendToken")
        XCTAssertTrue(BackendTransport.isReady(defaults: defaults))

        // Naming the shipped address explicitly is the same state as leaving it
        // blank, and must not be read as "a backend of my own with no gate".
        defaults.set(BackendTransport.bundledDefaultURL, forKey: "cloudBackendURL")
        defaults.removeObject(forKey: "cloudBackendToken")
        XCTAssertFalse(BackendTransport.isReady(defaults: defaults))

        // Somebody else's backend with no token is a real backend — a service run
        // without `BACKEND_TOKEN` accepts everyone. Refusing it here would turn a
        // working setup into "no cloud model".
        defaults.set("https://my-own-backend.example.com", forKey: "cloudBackendURL")
        XCTAssertTrue(
            BackendTransport.isReady(defaults: defaults),
            "a self-hosted backend with no gate is still a working backend")

        // And a value that is not a web address is not ready however it is dressed.
        defaults.set("not a url", forKey: "cloudBackendURL")
        defaults.set("s3cret", forKey: "cloudBackendToken")
        XCTAssertFalse(BackendTransport.isReady(defaults: defaults))
    }

    /// The constant itself has to be a URL the transport will accept.
    ///
    /// Worth its own assertion rather than trusting the test above: the fallback
    /// runs `bundledDefaultURL` through exactly the same two questions as a typed
    /// value, so a typo in it does not fail loudly — it returns nil from every
    /// `configured()` call in all three processes and restores the original bug
    /// with no error anywhere.
    func testTheBundledBackendURLIsOneTheTransportAccepts() throws {
        let url = try XCTUnwrap(URL(string: BackendTransport.bundledDefaultURL))
        XCTAssertEqual(url.scheme, "https", "a keyboard must not post the user's text over http")
        XCTAssertNotNil(url.host)
    }
}
