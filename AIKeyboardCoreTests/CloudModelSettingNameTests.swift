import XCTest

@testable import AIKeyboardCore
@testable import AIKeyboardShared

/// One key, named once, and every dead end pointing at that name.
///
/// `cloudBackendURL` is read by three processes and, before this, was written by
/// one field titled "Where the screen is read". So a Hebrew rewrite failed with
/// "no cloud model is set up" and named nowhere, and the screen-context refusal
/// named a screen that had nothing to do with rewriting. These assert the property
/// that stops that recurring: the sentences are built from one constant.
final class CloudModelSettingNameTests: XCTestCase {

    /// The four failures that dead-end on the missing backend all name the same
    /// row. Each of these used to stop at "no cloud model is set up", or point at
    /// Screen Context, which is where a user goes to record their screen and not
    /// where they go when Hebrew Fix fails.
    func testEveryDeadEndNamesWhereTheCloudModelIsSetUp() {
        let messages: [(String, String)] = [
            ("unsupportedLanguage", AIEngineError.unsupportedLanguage(.hebrew).message),
            ("cloudNotConfigured", AIEngineError.cloudNotConfigured.message),
            ("deviceNotSupported", AIEngineError.deviceNotSupported.message),
            ("notConfigured", ScreenContextEndReason.notConfigured.recovery)
        ]
        for (name, message) in messages {
            XCTAssertTrue(
                message.contains(BackendTransport.settingsPath),
                "\(name) reports a missing cloud model and names nowhere to go: \(message)")
        }
    }

    /// The path has to be a path — a screen the app draws, reachable by the words
    /// in it. `CloudModelView` is the row; this is the half a unit test can hold,
    /// and it is what fails if somebody renames the row without renaming this.
    func testTheSettingsPathNamesTheSectionAndTheRow() {
        XCTAssertEqual(BackendTransport.settingsPath, "Settings › AI › Cloud model")
        XCTAssertTrue(BackendTransport.setUpRecovery.contains(BackendTransport.settingsPath))
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
