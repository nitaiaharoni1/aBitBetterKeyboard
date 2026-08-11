import XCTest

@testable import AIKeyboardCore
@testable import AIKeyboardShared

/// One recovery sentence, used wherever a missing cloud model dead-ends.
///
/// `cloudBackendURL` is read by three processes. Before attestation, failures
/// pointed at a field titled "Where the screen is read" or said nothing useful.
/// These assert the property that stops that recurring: every dead end names the
/// same recovery — open the app and let it reconnect.
final class CloudModelSettingNameTests: XCTestCase {

    /// The four failures that dead-end on the cloud all say the same next step.
    func testEveryDeadEndNamesTheSameRecovery() {
        let messages: [(String, String)] = [
            ("unsupportedLanguage", AIEngineError.unsupportedLanguage(.hebrew).message),
            ("cloudNotConfigured", AIEngineError.cloudNotConfigured.message),
            ("deviceNotSupported", AIEngineError.deviceNotSupported.message),
            ("notConfigured", ScreenContextEndReason.notConfigured.recovery)
        ]
        for (name, message) in messages {
            XCTAssertTrue(
                message.contains(BackendTransport.setUpRecovery),
                "\(name) reports a missing cloud model and names nowhere to go: \(message)")
        }
    }

    /// The settings path still names a real row for the Debug URL field; the
    /// shipping recovery no longer points there, because attestation filled the
    /// token and there is nothing left for the user to type.
    func testTheSettingsPathNamesTheSectionAndTheRow() {
        XCTAssertEqual(BackendTransport.settingsPath, "Settings › AI › Cloud model")
        XCTAssertEqual(BackendTransport.setUpRecovery, "Open AI Keyboard once to reconnect.")
    }

    /// The screen-context refusal no longer claims to be about screen reading
    /// alone, because the setting it is missing is not.
    func testTheScreenContextRefusalNamesTheCloudModel() {
        let explanation = ScreenContextEndReason.notConfigured.explanation
        XCTAssertTrue(
            explanation.localizedCaseInsensitiveContains("cloud model"),
            "the ending blames screen reading for a setting four other features share: \(explanation)")
        XCTAssertFalse(
            explanation.localizedCaseInsensitiveContains("in this build"),
            "there is a screen for this now, so it is not something the build withheld")
    }
}
