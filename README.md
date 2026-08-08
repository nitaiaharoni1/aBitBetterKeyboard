# AI Keyboard — mock UI

A running SwiftUI mock of the keyboard described in `plan.md`: a Hebrew/English
iOS keyboard with AI text actions, dictation, and screen-context replies.

**Everything is faked.** No network, no model, no microphone, no screen capture.
The point is to judge the interaction and the layout, not the intelligence.

```
AIKeyboard.xcodeproj
├── AIKeyboard/               companion app
├── AIKeyboardExtension/      the keyboard extension (thin host)
├── AIKeyboardUITests/        screenshot walkthrough
└── Packages/AIKeyboardCore/  design system, keyboard UI, mock engines
```

The entire keyboard lives in `AIKeyboardCore`, not in the extension target. The
extension is ~70 lines that host `KeyboardView`. That split is deliberate: it
lets the companion app render the *real* keyboard in onboarding and in the
playground, so the product can be felt before iOS has been talked into
installing anything.

## Running it

```bash
open AIKeyboard.xcodeproj      # ⌘R, iPhone 17 Pro simulator
```

To use it as an actual keyboard, install the app, then Settings → General →
Keyboard → Keyboards → Add New Keyboard → AI Keyboard. Everything except the
system key-click works without Full Access.

The fastest way to see it is Home → **Try the keyboard**, which runs the same
keyboard against an in-memory document.

Swift files are formatted with Apple's `swift-format` (bundled with Xcode), using
the 4-space `.swift-format` config at the repo root:

```bash
xcrun swift-format --in-place --recursive \
  AIKeyboard AIKeyboardExtension AIKeyboardUITests Packages
```

## What's built

**Keyboard**
- English QWERTY and Hebrew layouts with system-matched metrics (42pt keys,
  6/12pt gaps), press callouts, accelerating delete, shift/caps, numbers and
  symbols planes
- Hebrew is 8/10/9 keys, has no shift key, and mirrors delete to the leading
  edge — because Hebrew has no case and reads right to left
- Suggestion bar with three fixed slots, emoji on one edge and the AI sparkle on
  the other
- Code-switching predictions: Latin words typed inside a Hebrew sentence get
  offered from a loanword list and tagged with the language they came from
- Emoji panel, nine categories, plain Unicode with no bundled images
- AI panel: Reply, Fix, Rewrite, Tone, each with a loading state and results you
  apply with one tap
- Dictation panel with a live waveform, a word-by-word streaming transcript, and
  a mixed-language indicator
- Screen-context strip: live capture indicator plus one-tap Reply

**Companion app**
- Six-step onboarding ending in a working keyboard
- Home with session state, setup checklist, playground, stats
- Screen Context: start/stop, live frame counters, what it does and does not do
- Languages, personal dictionary, settings, paywall

## Design decisions worth arguing with

**The sparkle and emoji sit in the suggestion bar, not the bottom row.** Both act
on text you are looking at rather than characters you are inserting, and it
leaves the bottom row close to the system layout where muscle memory lives.

**Autocorrect defaults to not correcting.** A space commits what you typed unless
the correction is confident: a missing apostrophe at any length, or four-plus
letters that are not already a word. The first version of this turned `I` into
`idea`, which is exactly how autocorrect earns its reputation.

**AI actions are small and reversible, never a chat box.** Fix and Rewrite show
you the before and after and let you decline. Nothing is applied silently.

**Reply leads the AI menu and explains itself when it cannot run.** Tapping it
without a capture session shows what screen context is and offers to start one,
rather than being greyed out with no reason given.

**The brand gradient only appears on AI moments.** Everything else is system
grey, so the keyboard reads as native rather than as a web page glued to the
bottom of the screen.

## Constraints the mock takes seriously

These shape the UI, so they are modelled rather than glossed over.

**A keyboard extension cannot open the microphone.** Dictation says "Recording
runs in the AI Keyboard app" because in the real build the audio session lives in
the main app and hands the transcript back. This is the part most likely to break
on an iOS update, and it is worth prototyping before anything else.

**Screen context is a session, not a permission.** Apple's persistent-capture
entitlement is meant for remote-desktop apps, so "allow once, works forever" is
not something to build on. The user starts a session, it is visible the whole
time it runs, and it stops. That is why Screen Context is on Home rather than in
onboarding: it is something you start, not something you set up once.

**Capture is never silent.** iOS shows its own indicator; the keyboard shows a
red dot and the message it read. The Screen Context screen also lists what the
feature will not do, including protected content blacking itself out.

**Reading a Hebrew screen means the screenshot leaves the device.** Apple's text
recogniser has no Hebrew — 30 languages, measured on both iOS and macOS, and
Arabic is one of them, so it is not a right-to-left limitation. Over the 30
screens in `Bar/screen-context/` it recovers 100% of the expected message on
English screens and 13% on Hebrew ones. So `RoutedScreenReader` reads what it
can on device and sends the rest to the cloud, and it decides which is which
without ever naming a script: `VNDetectTextRectanglesRequest` finds text by
shape regardless of language, so comparing regions *found* against regions
*read* measures "there is writing here I could not read" directly. No Hebrew or
mixed screen is ever kept on device. That asymmetry is deliberate: a misread
Hebrew screen produces a confident wrong reply in the user's name, while an
unnecessary cloud call costs five seconds.

**The on-device half is not currently earning its place, and the honest numbers
say so.** Measured end to end on iOS: routed scores sender 26/30 and message
24/30 within 90%, while asking the cloud for every frame scores 29/30 and 26/30.
Vision behaves differently on iOS than on macOS — it answers three frames there
that it correctly refuses on macOS, including the one whose only right answer is
silence. Two things are still open and are being measured rather than argued:
whether Vision can run at all inside the ~48 MB a keyboard extension gets or the
50 MB a broadcast extension gets, and whether the privacy gain of keeping eight
English frames on the device is worth three points of accuracy. If the answer to
the first is no, the second is moot and every screen read goes to the cloud.

**Full Access is optional in English and effectively required in Hebrew.** Typing,
autocorrect, predictions and emoji work without it. The on-device AI path works
without it too — but only for the 23 languages Apple's model supports, and Hebrew
is not one of them, so every Hebrew AI action needs the network and therefore Full
Access. Two things follow. iOS only lets a keyboard extension reach a shared
container once Full Access is granted, so without it the keyboard falls back to
shipped defaults instead of the settings the user chose in the app. And for the
audience this keyboard is built for, "optional" is the wrong word.

## The mocks, and what replaces them

| Mock | Real thing |
|---|---|
| `MockSuggestionEngine` | local autocorrect + a small next-word model |
| ~~`MockAI`~~ — now `RoutedIntelligence` | **Done.** Apple Foundation Models on device for the languages it lists, a cloud LLM behind it for the rest. Hebrew is not one of Apple's supported languages, so it needs the cloud path. The cloud provider sits behind a protocol; a shipped app cannot hold cloud credentials, so it must point at your own backend. The direct-to-Vertex client used to score `Bar/ai-text/` lives in the harness and is deliberately not in the app target. |
| `MockDictation` | Runs in the main app. **`SpeechTranscriber` cannot do Hebrew** — measured, 30 locales, none of them `he`. Legacy `SFSpeechRecognizer` has `he-IL` but reports no on-device support here, so Hebrew dictation means cloud STT (Deepgram Nova-3 is the candidate `plan.md` names). |
| `MockScreenContext` | **Reading a frame is done and measured** — `RoutedScreenReader`, scored against `Bar/screen-context/`. **Getting** a frame is not: ScreenCaptureKit is `iOS 27.0+` and absent from the iOS 26.2 SDK this project compiles against, and the ReplayKit route needs a broadcast upload extension target that does not exist yet. `ScreenContextSession.submit(_:appName:appIcon:)` is the seam both plug into. |
| ~~`SharedStore`~~ | **Done.** Both targets carry the App Group entitlement and share one suite. |
| `MockTextTarget` | `UITextDocumentProxy`, already wired via `ProxyTextTarget` |

`SharedStore` now writes to the App Group container, and the keyboard extension
reads what the app wrote. `SharedStore.storage` says which of the two stores an
instance actually got: `.appGroup`, or `.processLocal` when the container was out
of reach, which it also logs as an error rather than pretending to be shared.

Verify it end to end with `Scripts/prove-app-group.sh`. The check that matters is
the last one — it turns English off in the app, brings the keyboard up in a real
text field, and confirms the extension process, which iOS runs separately,
rendered Hebrew because of it. A unit test cannot show this: a process always
sees its own writes.

## Testing

`AIKeyboardUITests` drives the app by accessibility identifier and writes a PNG
per screen. It runs inside the simulator, so it does not take over the pointer.

```bash
# Run the suite, keeping the screenshots
TEST_RUNNER_SHOT_DIR=/tmp/shots xcodebuild test \
  -project AIKeyboard.xcodeproj -scheme AIKeyboard \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Coverage report
xcodebuild test -project AIKeyboard.xcodeproj -scheme AIKeyboard \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -resultBundlePath /tmp/AIKeyboard.xcresult
xcrun xccov view --report /tmp/AIKeyboard.xcresult
```

Four tests live in `AIKeyboardUITests/DemoWalkthroughTests.swift`. There are no
unit tests yet; see `.claude/docs/testing.md`.

## Not built

- The keyboard extension runs in a real text field — `Scripts/prove-app-group.sh`
  drives it — but only far enough to prove it reads shared settings; the panels
  are still exercised through the in-app playground
- Landscape, iPad layouts, Dynamic Type above the default size
- Real StoreKit, accounts, or any backend
