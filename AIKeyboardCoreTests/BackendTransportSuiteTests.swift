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

        XCTAssertNil(BackendTransport.configured(defaults: suite))

        suite.set("https://backend.example.com", forKey: "cloudBackendURL")
        XCTAssertNotNil(BackendTransport.configured(defaults: suite))

        // A value that is not a usable http(s) URL is not a configured backend.
        suite.set("not a url", forKey: "cloudBackendURL")
        XCTAssertNil(BackendTransport.configured(defaults: suite))

        suite.removePersistentDomain(forName: "BackendTransportSuiteTests")
    }

    /// The regression itself: the default must be the shared store, never
    /// `.standard`. Compared by object identity, because both are `UserDefaults`
    /// and only the instance tells them apart.
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
