import XCTest

@testable import AIKeyboardCore

/// The backend URL is written by the app and read by the keyboard extension, so
/// it has to come from the shared suite. `UserDefaults.standard` inside an
/// extension is that process's own container: the setting would look saved in
/// the app and be permanently absent in the keyboard, and nothing would report
/// an error. That shipped once.
final class BackendTransportSuiteTests: XCTestCase {

    func testConfiguredReadsWhicheverStoreItIsGiven() {
        let suite = UserDefaults(suiteName: "BackendTransportSuiteTests")!
        suite.removePersistentDomain(forName: "BackendTransportSuiteTests")

        // An empty store is a stock install, and a stock install now reaches the
        // backend this build ships with — see
        // `CloudIntelligenceTests.testAnAbsentOrEmptyURLFallsBackToTheBundledBackend`
        // for why that stopped being nil. What proves *this* suite is the one being
        // read is the pair below: a value put here is honoured, and a bad value put
        // here is refused, neither of which could happen against `.standard`.
        XCTAssertNotNil(BackendTransport.configured(defaults: suite))

        suite.set("https://backend.example.com", forKey: "cloudBackendURL")
        XCTAssertNotNil(BackendTransport.configured(defaults: suite))

        // A value that is not a usable http(s) URL is not a configured backend.
        suite.set("not a url", forKey: "cloudBackendURL")
        XCTAssertNil(BackendTransport.configured(defaults: suite))

        suite.removePersistentDomain(forName: "BackendTransportSuiteTests")
    }

    /// The bearer token rides in the same store as the URL, and for the same
    /// reason: the app writes both and two extensions read them.
    ///
    /// A backend without one is still a backend — a service run locally with no
    /// `BACKEND_TOKEN` accepts everyone, and refusing to configure would turn a
    /// working setup into "no cloud model". A backend *with* one whose token the
    /// app has not been given fails at the first call with a 401, which the
    /// client maps to `cloudNotConfigured`: the honest reading, since a backend
    /// this app cannot authenticate to is one it does not have.
    func testTheTokenIsOptionalAndComesFromTheSameStore() throws {
        let suite = UserDefaults(suiteName: "BackendTransportTokenTests")!
        defer { suite.removePersistentDomain(forName: "BackendTransportTokenTests") }
        suite.removePersistentDomain(forName: "BackendTransportTokenTests")

        suite.set("https://backend.example.com", forKey: "cloudBackendURL")
        XCTAssertNotNil(
            BackendTransport.configured(defaults: suite),
            "a backend with no token configured is still a backend")

        for blank in ["", "   ", "\n"] {
            suite.set(blank, forKey: "cloudBackendToken")
            XCTAssertNotNil(
                BackendTransport.configured(defaults: suite),
                "whitespace is not a token, and must not become 'Bearer    '")
        }

        suite.set("  s3cret  ", forKey: "cloudBackendToken")
        XCTAssertNotNil(BackendTransport.configured(defaults: suite))
    }

    /// …and the token actually reaches the wire.
    ///
    /// Worth its own test rather than trusting the one above: reading a setting
    /// and sending a header are two different things, and the failure mode of
    /// getting the second wrong is a backend that 401s every call while the app
    /// insists it is configured. Intercepted with a `URLProtocol` so no request
    /// leaves the machine.
    func testTheTokenIsSentAsABearerHeaderAndOmittedWhenAbsent() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RecordingProtocol.self]
        let session = URLSession(configuration: configuration)
        let url = URL(string: "https://backend.example.com")!
        let request = CloudRequest(
            instructions: "i", prompt: "p", fields: [CloudField("text", "d")])

        RecordingProtocol.reset()
        _ = try? await BackendTransport(baseURL: url, token: "s3cret", session: session)
            .send(request)
        XCTAssertEqual(
            RecordingProtocol.lastHeaders?["Authorization"], "Bearer s3cret",
            "a configured token has to reach the wire, not just the settings store")

        RecordingProtocol.reset()
        _ = try? await BackendTransport(baseURL: url, token: nil, session: session).send(request)
        XCTAssertNil(
            RecordingProtocol.lastHeaders?["Authorization"],
            "no token means no header at all, not an empty bearer")
    }

    /// The regression itself: `BackendTransport.configured()`'s default store must
    /// be the shared one, never `.standard`.
    ///
    /// **It was declared inside `RecordingProtocol`, a `URLProtocol` subclass, so
    /// XCTest never ran it.** A test method only runs when it is a method on an
    /// `XCTestCase`; anywhere else it compiles, reads correctly, and is dead. The
    /// regression it names — the keyboard reading a store the app never wrote to —
    /// was therefore unguarded for as long as this file has existed.
    func testDefaultStoreIsTheSharedOneNotStandard() {
        // In a unit-test process the App Group is usually out of reach, so
        // SharedStore falls back to .standard and comparing the two instances
        // proves nothing here. Assert the property that survives either way:
        // `configured()` must consult SharedStore's store, so writing there is
        // what makes a backend appear.
        let store = SharedStore.shared.userDefaults
        let original = store.string(forKey: "cloudBackendURL")
        defer {
            if let original {
                store.set(original, forKey: "cloudBackendURL")
            } else {
                store.removeObject(forKey: "cloudBackendURL")
            }
        }

        store.set("https://shared.example.com", forKey: "cloudBackendURL")
        XCTAssertNotNil(
            BackendTransport.configured(),
            "configured() must read SharedStore.shared.userDefaults")
    }
}

/// Answers every request with the smallest valid body and records what it was
/// asked. `URLProtocol` subclasses are registered process-wide, so this is
/// deliberately inert unless a session is configured with it.
private final class RecordingProtocol: URLProtocol {
    nonisolated(unsafe) private(set) static var lastHeaders: [String: String]?

    static func reset() { lastHeaders = nil }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastHeaders = request.allHTTPHeaderFields
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: nil,
            headerFields: ["content-type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"fields":{"text":"ok"}}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
