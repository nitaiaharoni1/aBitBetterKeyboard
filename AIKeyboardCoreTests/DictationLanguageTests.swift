import Speech
import XCTest

/// Pins the two measurements behind `CloudDictation`'s doc comment: legacy
/// `SFSpeechRecognizer` — distinct from iOS 26's `SpeechTranscriber`, which
/// `SpeechLanguageTests` in `ScreenReaderTests.swift` already pins as having no
/// Hebrew locale at all — does list Hebrew, but only for network recognition.
///
/// **Together they are why every transcription in this product is a network
/// call.** Hebrew is listed, so the language is not the problem; it is listed
/// without on-device support, so there is no local engine to fall back to, and
/// `SpeechTranscriber` does not list it at all. `CloudDictation` is the
/// consequence.
///
/// This does not touch the other half of that finding: that a keyboard
/// extension has no path to the microphone regardless of what any recognizer
/// supports. That is Apple's own documentation, not something a test on this
/// Simulator can measure, and it is cited by URL and quote in
/// `DictationChannel` rather than pinned here.
final class LegacySpeechRecognizerLanguageTests: XCTestCase {

    func testHebrewIsAmongTheSupportedLocales() {
        let identifiers = SFSpeechRecognizer.supportedLocales().map(\.identifier)

        XCTAssertTrue(
            identifiers.contains("he-IL"),
            """
            SFSpeechRecognizer no longer lists he-IL. If this ever fails, re-read \
            supportsOnDeviceRecognition for it before touching CloudDictation — \
            losing the locale entirely is a bigger change than gaining on-device \
            support for it. Locales seen: \(identifiers.sorted())
            """)
    }

    /// Recorded rather than asserted, the same call `SpeechLanguageTests` makes
    /// for the newer API: this flag tracks installed speech assets on the
    /// machine running the test as much as it tracks true device capability
    /// (`fr-FR` also reads `false` here despite French shipping on-device
    /// recognition on real hardware), so a hard assertion on it would be
    /// pinning an environment artifact rather than a fact about Hebrew. `en-US`
    /// is the control that proves the flag is not simply always `false`.
    func testOnDeviceSupportIsRecordedNotAssumed() throws {
        let locales: [(id: String, expectOnDevice: Bool?)] = [
            ("en-US", true), ("he-IL", nil), ("fr-FR", nil)
        ]

        for (id, expectOnDevice) in locales {
            let recognizer = try XCTUnwrap(
                SFSpeechRecognizer(locale: Locale(identifier: id)),
                "SFSpeechRecognizer(locale:) returned nil for \(id)")
            print(
                "DICTATION \(id): isAvailable=\(recognizer.isAvailable) "
                    + "supportsOnDeviceRecognition=\(recognizer.supportsOnDeviceRecognition)")
            if let expectOnDevice {
                XCTAssertEqual(recognizer.supportsOnDeviceRecognition, expectOnDevice)
            }
        }
    }
}
