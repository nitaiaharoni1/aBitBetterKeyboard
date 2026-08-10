import XCTest

@testable import AIKeyboardCore

final class SessionTokenTests: XCTestCase {

    /// A JWT this test builds itself. Unsigned on purpose: the app cannot verify
    /// a signature it has no secret for, and must never behave as though it can.
    private func token(expiringAt seconds: Int) -> String {
        let payload = #"{"sub":"device-1","exp":\#(seconds)}"#
        let encoded = Data(payload.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "header.\(encoded).signature"
    }

    func testTheExpiryIsReadOutOfTheToken() {
        let expiry = SessionToken.expiry(of: token(expiringAt: 1_800_000_000))
        XCTAssertEqual(expiry, Date(timeIntervalSince1970: 1_800_000_000))
    }

    func testSomethingThatIsNotAJWTHasNoExpiry() {
        XCTAssertNil(SessionToken.expiry(of: "not-a-token"))
        XCTAssertNil(SessionToken.expiry(of: ""))
        XCTAssertNil(SessionToken.expiry(of: "a.b.c"))
    }

    func testAnExpiredSessionTokenIsNotAReadyBackend() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defaults.set(token(expiringAt: 1), forKey: "cloudSessionToken")
        XCTAssertFalse(BackendTransport.isReady(defaults: defaults))
    }

    func testAnUnexpiredSessionTokenIsAReadyBackend() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let future = Int(Date().addingTimeInterval(60 * 60 * 24).timeIntervalSince1970)
        defaults.set(token(expiringAt: future), forKey: "cloudSessionToken")
        XCTAssertTrue(BackendTransport.isReady(defaults: defaults))
    }

    func testATypedTokenWinsOverAnAttestedOne() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defaults.set("typed-by-a-developer", forKey: "cloudBackendToken")
        defaults.set(token(expiringAt: 1), forKey: "cloudSessionToken")
        // The expired session token must not be what goes on the wire, and the
        // expired session token must not make `isReady` false either: a typed
        // token is a complete setup on its own.
        XCTAssertTrue(BackendTransport.isReady(defaults: defaults))
    }
}
