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

**Full Access is optional.** Typing, autocorrect, predictions, emoji and the
on-device AI path all work without it. It buys cloud rewrites and the system key
click, and the onboarding says so plainly.

## The mocks, and what replaces them

| Mock | Real thing |
|---|---|
| `MockSuggestionEngine` | local autocorrect + a small next-word model |
| `MockAI.fix/variants/replies` | Apple Foundation Models on device, cloud LLM as fallback |
| `MockDictation` | `SpeechAnalyzer`/`SpeechTranscriber` or Deepgram, running in the main app |
| `MockScreenContext` + `ScreenContextSession` | `SCStream` full-display capture, `screen-capture` background mode, Vision OCR |
| `SharedStore` | same file, pointed at a real App Group suite |
| `MockTextTarget` | `UITextDocumentProxy`, already wired via `ProxyTextTarget` |

`SharedStore` already asks for the App Group suite by name, so no code change is
needed to switch it on. What is missing is the entitlement: there is no
`.entitlements` file in the project, so `UserDefaults(suiteName:)` returns
nothing usable and the store falls back to `.standard`. **The app and the
keyboard do not share state today** — each process keeps its own copy.

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

- The keyboard extension is built and embedded but has not been exercised inside
  a host app; all of its UI is shared with the in-app playground, which has been
  verified end to end
- App Group entitlements (the mock keeps per-process state instead)
- Landscape, iPad layouts, Dynamic Type above the default size
- Real StoreKit, accounts, or any backend
