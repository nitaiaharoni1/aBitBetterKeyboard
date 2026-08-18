# Dictation's front door

Why starting a dictation session is an App Intent that foregrounds the app, what
a Control Center control and a Live Activity would add on top of it, and exactly
what target work those two need. Read `.claude/rules/dictation.md` first: every
constraint below is downstream of the one error code that shaped the feature.

## What ships now

`AIKeyboard/Intents/DictationIntents.swift` and
`AIKeyboard/Intents/AIKeyboardShortcuts.swift`, in the **main app target**, no new
Xcode target and no `.pbxproj` edit — `AIKeyboard/` is a
`PBXFileSystemSynchronizedRootGroup`, so a new directory under it compiles into
the app.

- **`StartDictationIntent`** — `openAppWhenRun = true` (and
  `supportedModes = .foreground` on iOS 26, where the first is deprecated). Calls
  `DictationService.shared.start(minutes:)` with `DictationService.noSessionLimit`,
  the same entry point and the same length Home's card uses. Already running answers so, rather than restarting. A refusal is a thrown
  `DictationIntentError`, carrying `DictationService.lastError`, so Shortcuts
  shows a failure as a failure instead of reporting success over a microphone
  that never opened.
- **`StopDictationIntent`** — no `openAppWhenRun`, so it runs in the background,
  in this app's own process. While a session is live that process is alive (the
  `audio` background mode is what keeps it running), so the singleton it reaches
  is the one holding the microphone. With no session, iOS launches the app in the
  background, `isRunning` is false there, and "no session running" is the true
  answer: a session cannot outlive the process that owns the microphone.
- **`AIKeyboardShortcuts`** — an `AppShortcutsProvider` with three start phrases
  and two stop phrases, which is what puts both intents in Spotlight, in the
  Shortcuts app, and in the Action Button's picker without the user building
  anything.

**No extend intent.** There is no API to push an existing session's expiry out:
the deadline is written once by `DictationChannelWriter.begin` into the shared
page, and `DictationService.start` returns early for a session that is already
running, so "extend" today can only mean stop-then-start — which drops the
microphone, needs the foreground again (see below), and resets the session id the
keyboard is holding. Restarting through the same start intent is the same number
of presses without the new failure mode.

## The background-start rule, and what was actually verified

**An App Intent cannot start this app's microphone without foregrounding it, in
this build.** Three things, two of them checked against the SDK on this machine
(iPhoneOS26.2, Xcode's `AppIntents.swiftinterface`) and Apple's published
documentation:

1. The OS rule the whole feature is built on: an app in the background cannot
   *begin* recording (`AVAudioSession` 561145187, `cannotStartRecording`), while a
   session that is already active survives an app switch under the `audio`
   background mode. `DictationService.start`'s own doc comment states the
   precondition, and it is why dictation is a session rather than a button.
2. `AudioRecordingIntent` is the one API that lifts that rule for an intent. It
   exists — `public protocol AudioRecordingIntent : SystemIntent`, `@available(iOS
   18.0, macOS 15.0, watchOS 11.0, tvOS 18.0, visionOS 2.0)` — and its
   documentation attaches a condition in an Important aside: *"In iOS, iPadOS, and
   watchOS, when you adopt the AudioRecordingIntent protocol, you must start a
   Live Activity when you begin the audio recording and keep it active as long as
   you record audio. If you don't start a Live Activity, the audio recording
   stops."* A Live Activity means ActivityKit and a widget extension target, which
   this project does not have.
3. It needs iOS 18; this app deploys to iOS 17 (`IPHONEOS_DEPLOYMENT_TARGET =
   17.0`).

So the honest shape today is foreground-and-start. A visible app switch the user
asked for is still a large improvement on hunting for the app, and it is far
better than a shortcut that silently records nothing.

**Not verified, and not verifiable here:** none of this has run on a device. A
simulator cannot settle background audio, and `Scripts/prove-dictation.sh` proves
the channel rather than the recording. What specifically remains unknown is
whether an `AudioRecordingIntent` *with* a Live Activity does in fact begin
recording from the background when run from Shortcuts or the Action Button rather
than from a Control Center control; Apple documents the Live Activity condition
but not the set of surfaces the allowance covers.

## What a Control Center control and a Live Activity would add

**The Live Activity is the bigger of the two, and it is not only a means to the
background start.** A live session is invisible once the user leaves the app:
Home's card says LIVE and the keyboard's microphone key turns red per utterance,
but on the Lock Screen there is only the system's orange recording dot. A Live
Activity would put "Dictation on, 4:32 left" with a Stop button on the Lock
Screen and in the Dynamic Island for the whole session, which is the missing
answer to "is the microphone still open?" and a second, always-reachable Stop.

**The Control Center control** is a toggle on the Control Center page, on the Lock
Screen, and assignable to the Action Button, that starts and stops the session
without opening anything. That is the version of this feature with no app switch
at all, and it is only reachable through step 2 above.

What they need, precisely:

- **A new WidgetKit extension target** in `AIKeyboard.xcodeproj` (`objectVersion =
  77`; give it its own `PBXFileSystemSynchronizedRootGroup` to match the other
  five). Both the Live Activity UI and any `ControlWidget` must live in a widget
  extension; neither can live in the app.
- **`NSSupportsLiveActivities = true`** in `AIKeyboard/Info.plist` (the app's, not
  the extension's) — that file is already a partial plist merged into the
  generated one, so the key goes beside `UIBackgroundModes`.
- **The App Group entitlement** (`group.com.nitai.aikeyboard`) on the new target if
  the widget reads session state from the shared page rather than only from the
  activity's own content state. If it does, it links **`AIKeyboardShared`**, never
  `AIKeyboardCore` — the same rule `AIKeyboardBroadcast` follows, for the same
  memory reason, and widget processes have a tighter budget than the app.
- **`ActivityKit`** in `DictationService`: request the activity where the engine
  starts (`DictationService+Lifecycle.start`), update it from the existing 10 Hz
  poll (`DictationService+Polling`), and end it in `stop(_:)` beside
  `writer.end(_:)`. The session already has everything the activity needs —
  `expiresAt`, `phase`, `level`.
- **Protocol conformances**: `StartDictationIntent` gains `AudioRecordingIntent`
  (iOS 18+) and `LiveActivityIntent` (iOS 17+, the protocol that lets an intent
  start and update a Live Activity from the background), and drops
  `openAppWhenRun` / switches `supportedModes` to `.background`. Both must be
  `@available`-gated or the app's deployment target moved off 17. A Control Center
  toggle also wants a `SetValueIntent<Bool>` (iOS 18+) rather than the two
  separate intents, because a toggle carries the value it is being set to.
- **A device to prove any of it.** The simulator cannot show that background
  recording actually starts.

## Two findings this work turned up

**A session had no end, and after this work it still has none, on purpose.**
This was found as a defect and resolved as a decision, so both halves are worth
keeping.

What was found: `SharedStore.dictationSessionMinutes` defaulted to 5, offered
5 / 15 / 60, and its own doc comment explained at length why there was
deliberately no "never" — while both existing starters, `HomeDictationCard` and
`RootView.beginDictationHandoffIfFresh`, passed `minutes: 0`, which is exactly
"never". `DictationChannelWriter.begin` writes `expiresAt = 0` and
`DictationService+Polling` never expires such a session. `StartDictationIntent`,
written by this work, was the only reader. And `SharedStore+Persistence`
validated a loaded value against the three choices, so `0` was not a number that
setting could hold: the two literals were bypassing the setting, not passing it.

What was decided (2026-08-18, by the repository's owner): **dictation is not
bounded at all.** A session is something the user starts and stops, and being cut
off mid-sentence is the worse failure. A bound was briefly applied to all three
starters and then removed from all three. The setting and its choices are
deleted; `DictationService.noSessionLimit` is the named constant every starter
now passes, and it carries the reasoning.

Two consequences to carry forward. `AIKeyboard/Info.plist`'s background-mode
comment used to justify the `audio` entitlement with "a session closes itself
after 5, 15 or 60 minutes"; it now says what is true, and it is the place to
start if App Review asks. And with no timeout, the keyboard's own red microphone
cap is the only continuous signal that a recording is live once the user has
switched apps — which raises the value of the Live Activity below rather than
lowering it.

**Siri cannot say "aBitBetterKeyboard".** Every `AppShortcutPhrase` must contain
the `\(.applicationName)` token, which expands to `CFBundleDisplayName`. Spotlight,
the Shortcuts app and the Action Button match on the shortcut's title instead, so
they are fine; only the spoken path suffers. The fix is an alternative-app-name
entry (`INAlternativeAppNames`, with a pronunciation hint) in
`AIKeyboard/Info.plist` — worth confirming the current key shape against Apple's
documentation before writing it, which was not possible here.

## Also not done

The intent foregrounds the app onto whatever screen it last showed. Landing on
Home, the way the keyboard's `aikeyboard://dictation/start` handoff does through
`RootView.beginDictationHandoffIfFresh`, needs `AIKeyboard/AIKeyboardApp.swift`,
which owns `selectedMainTab`.
