import AppIntents

/// The shortcuts the system offers before the user has built one.
///
/// An `AppShortcutsProvider` is what puts these intents in Spotlight, in the
/// Shortcuts app under this app's name, and in the Action Button's picker, and
/// it is the only way a spoken phrase reaches Siri without the user recording
/// anything themselves.
///
/// **Every phrase has to name the app, and this app's name is a hard one to
/// say.** The `\(.applicationName)` token is required in each phrase and expands
/// to the display name, "aBitBetterKeyboard". Spotlight, Shortcuts and the Action
/// Button match on `shortTitle` and on the intent's own title rather than on the
/// spoken phrase, so those three are unaffected; Siri is the surface that
/// suffers, and the fix is an alternative-app-name entry in
/// `AIKeyboard/Info.plist`, not anything in this file. See
/// `.claude/docs/dictation-front-door.md`.
struct AIKeyboardShortcuts: AppShortcutsProvider {

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartDictationIntent(),
            phrases: [
                "Start dictation in \(.applicationName)",
                "Start a \(.applicationName) dictation session",
                "Dictate with \(.applicationName)"
            ],
            shortTitle: "Start dictation",
            systemImageName: "mic.fill")

        AppShortcut(
            intent: StopDictationIntent(),
            phrases: [
                "Stop dictation in \(.applicationName)",
                "Stop the \(.applicationName) dictation session"
            ],
            shortTitle: "Stop dictation",
            systemImageName: "stop.fill")
    }
}
