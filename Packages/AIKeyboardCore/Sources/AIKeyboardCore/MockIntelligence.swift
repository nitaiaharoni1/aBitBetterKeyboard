import Foundation

// MARK: - Screen context
//
// Stands in for the ReplayKit broadcast session that runs in the main app and
// hands OCR'd text to the keyboard through the App Group. Nothing here captures
// anything; these are the messages a session would have read off the screen.
// (Capture API depends on deployment target: ReplayKit on iOS <=26, reportedly
// ScreenCaptureKit on iOS 27+. See ScreenContextSession.swift.)

public enum MockScreenContext {

    private static let samples: [ScreenContext] = [
        ScreenContext(
            appName: "WhatsApp",
            appIcon: "message.fill",
            sender: "שרה",
            message: "היי, אתה פנוי לארוחת ערב הערב? חשבתי על המקום החדש ביפו",
            language: .hebrew
        ),
        ScreenContext(
            appName: "Slack",
            appIcon: "number",
            sender: "Daniel",
            message: "Can you take the standup tomorrow? I have a conflict at 9.",
            language: .english
        ),
        ScreenContext(
            appName: "Messages",
            appIcon: "bubble.left.fill",
            sender: "Maya",
            message: "שלחתי לך את ה-deck, אפשר feedback עד מחר בצהריים?",
            language: .hebrew
        )
    ]

    public static func sample(at index: Int) -> ScreenContext {
        samples[index % samples.count]
    }

    public static var sampleCount: Int { samples.count }

    /// How long the picker plus stream start-up takes before frames arrive.
    public static let startupDelay: Duration = .milliseconds(900)
    /// How long the session watches before it reads something repliable.
    public static let firstReadDelay: Duration = .milliseconds(1400)
}

// MARK: - Dictation
//
// A scripted transcript that streams in word by word, for the onboarding demo
// and the app's playground. This stays a mock deliberately: the investigation
// below found the real thing categorically unavailable inside a keyboard
// extension, on any configuration, and a mock documented as necessary beats a
// real implementation that would silently refuse every time it runs in the
// shipping product.
//
// **The blocking finding, read from Apple's current documentation on
// 2026-08-08, not from memory.** "Configuring open access for a custom
// keyboard" — developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard —
// lists, verbatim, under the keyboard's *standard* sandbox (`RequestsOpenAccess`
// `false`, or the user has not granted Full Access): "No access to microphone
// and speaker." Enabling open access does not lift it: the same document's
// open-access capability list adds Location Services and Contacts (with
// permission), a shared container with the containing app, network access for
// server-side processing, and iCloud — and does not mention the microphone
// anywhere. This is not a permission dialog the user can grant; it is an OS
// sandbox boundary `AVAudioSession`/`AVAudioApplication` cannot cross from
// `AIKeyboardExtension`'s process regardless of what the user allows in
// Settings. The archived 2018 revision of the same guidance says it more
// bluntly: "Custom keyboards, like all app extensions in iOS 8.0, have no
// access to the device microphone, so dictation input is not possible." Nothing
// found while checking this suggests either statement has changed since.
//
// **Even where a mic-capable process exists, Hebrew dictation is not free.**
// `SFSpeechRecognizer.supportedLocales()` — the older, still-supported API,
// distinct from iOS 26's `SpeechTranscriber` — lists `he-IL` among 63 locales,
// verified independently on the iOS 26.2 Simulator and on a macOS 26.5.1 host.
// But on both, `SFSpeechRecognizer(locale: Locale(identifier: "he-IL"))!
// .supportsOnDeviceRecognition` reads `false`, so Hebrew would still need a
// network round trip even from a process that could reach the microphone at
// all. (That flag tracks installed speech assets more than true capability —
// `fr-FR` also reads `false` on both machines, though French ships on-device
// recognition on real hardware — so read this as "network required on the
// machines this was checked on," not as a permanent limit.) The newer API is
// worse, not better: `SpeechTranscriber.supportedLocales` has no Hebrew locale
// at all, independently reproduced here (30 locales) and already pinned by
// `SpeechLanguageTests` in `ScreenReaderTests.swift`.
//
// **But "the keyboard cannot record" is not the same as "dictation is
// impossible", and an earlier version of this comment ran the two together.**
// Gboard ships voice typing on iOS. It does not record in the keyboard — it
// cannot, the boundary above is real — it hands off to the *Gboard app*, which
// records and recognises, and the text comes back as keyboard input. So the
// product feature is demonstrably achievable on this platform, and the shape it
// takes is one this repo already has working for screen context: the sensor
// lives in the containing app, the result crosses the App Group, and the
// keyboard is a pure reader (`AIKeyboardShared`'s capture channel,
// `ScreenContextSession`).
//
// **What is genuinely unsettled is the trigger, and it carries review risk.**
// Screen context gets its trigger for free: the user starts the broadcast from
// inside the app by tapping Apple's own `RPSystemBroadcastPickerView`. Dictation
// has no equivalent. `UIApplication` is marked unavailable to app extensions, so
// `UIApplication.shared.open(_:)` does not compile here, and the widely-used
// workaround — walking the responder chain to find `UIApplication` and invoking
// `openURL:` by selector — is explicitly called out by Apple as not allowed and
// a likely rejection. `QA1924` permits `openURL` from a keyboard extension for
// exactly one destination, Keyboard settings, which is not this. Whatever Gboard
// relies on, this repo has not identified a documented API that does it.
//
// So the honest status is: **not blocked on the microphone, blocked on a
// supported hand-off.** The recording half would live in `AIKeyboard/`, the
// transcript would cross the App Group the same way a screen reading does, and
// the open question is how a tap inside the keyboard starts that without an API
// Apple sanctions — possibly it does not, and the user taps the app themselves.
// That is a product decision with an App Store consequence, not a coding task,
// which is why nothing here pretends to have made it.

public enum MockDictation {

    public struct Script: Sendable {
        public let words: [String]
        public let isRightToLeft: Bool
    }

    private static let scripts: [Script] = [
        Script(
            words: ["אני", "אשלח", "לך", "את", "ה-document", "מחר", "בבוקר,", "אחרי", "ה-standup"],
            isRightToLeft: true
        ),
        Script(
            words: ["Can", "you", "review", "the", "deck", "before", "the", "meeting", "tomorrow?"],
            isRightToLeft: false
        ),
        Script(
            words: ["בוא", "נעשה", "sync", "קצר", "על", "ה-roadmap", "של", "Q3"],
            isRightToLeft: true
        )
    ]

    public static func script(at index: Int) -> Script {
        scripts[index % scripts.count]
    }

    public static var scriptCount: Int { scripts.count }

    /// Gap between words while streaming. Uneven on purpose; a metronome reads as fake.
    public static func delay(forWordAt index: Int) -> Duration {
        let pattern: [Int] = [220, 180, 300, 160, 260, 200, 340, 190]
        return .milliseconds(pattern[index % pattern.count])
    }
}
