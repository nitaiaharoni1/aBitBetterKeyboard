# AI Keyboard — mock UI

A running SwiftUI mock of the keyboard described in `plan.md`: a Hebrew/English
iOS keyboard with AI text actions, dictation, and screen-context replies.

**The AI is real; the input to it is still partly faked.** Text actions and
screen reading call real models and are scored against frozen corpora in `Bar/`.
Typing suggestions and dictation are still mocks. Screen capture is now built up
to the read: the app hosts Apple's broadcast picker, a broadcast upload extension
fingerprints frames into a shared page, the keyboard asks it for a reading when
you tap Reply, and the capture process answers by encoding one frame and reading
it in the cloud. The whole loop is written. **None of the ReplayKit half has ever
run**, because the iOS Simulator ships no `replayd`, so no frame has ever reached
any of it. The table at the end says which parts are measured and which are only
compiled.

```
AIKeyboard.xcodeproj
├── AIKeyboard/               companion app
├── AIKeyboardExtension/      the keyboard extension (thin host)
├── AIKeyboardBroadcast/      ReplayKit broadcast upload extension (capture)
├── AIKeyboardUITests/        screenshot walkthrough
├── AIKeyboardCoreTests/      unit tests over AIKeyboardCore
├── Bar/                      frozen corpora the engines are scored against
└── Packages/AIKeyboardCore/  design system, keyboard UI, engines
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
  AIKeyboard AIKeyboardExtension AIKeyboardBroadcast AIKeyboardUITests AIKeyboardCoreTests Packages
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
- Screen-context strip: the capture indicator, the message that was read, and
  one-tap Reply; it also carries "paused" and "stopped unexpectedly, restart it
  in AI Keyboard"

**Companion app**
- Six-step onboarding ending in a working keyboard
- Home with session state, setup checklist, playground, stats
- Screen Context: Apple's broadcast picker, the capture process's own counters,
  a sample conversation to try it without starting anything, what it does and
  does not do
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
without a capture session says what screen context is and where to start it,
rather than being greyed out with no reason given. It says it in words: only
iOS's own picker can start a broadcast, so a button there would have nothing
honest to do.

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

**And the app cannot start it either.** `RPSystemBroadcastPickerView` is the only
supported entry point and its button is system-vended, so no code can press it —
the Screen Context screen hosts the picker, says what the three taps after it
look like, and says plainly that only iOS can start this. The same constraint is
why the keyboard's Reply panel, when nothing is running, is words rather than a
button: it used to offer "Start screen context", which started the scripted
sample and no capture at all.

**Capture is never silent, and a session that ends says so.** iOS shows its own
indicator; the keyboard shows a red dot — red only while frames are actually
being sampled — and the message it read. A session that stops without the user
stopping it reads as "stopped unexpectedly" with a way back, never as "screen
context is off", which is the only signal a jetsam kill leaves behind: it fires
no ReplayKit callback at all, so the evidence is a heartbeat that stopped. The
Screen Context screen also lists what the feature will not do. One item there is
hedged rather than claimed: apps can exclude themselves from a recording and
banking and video apps usually do, but that has not been verified on a device
here, and nothing in the design relies on it.

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
silence.

**So in the ReplayKit capture flow every screen read goes to the cloud, English
included, and it goes only when you tap Reply.** The order of the two open
questions was backwards: the accuracy one is answered above, on iOS, and it
decides this on its own. What the Screen Context screen therefore says is that
tapping Reply sends one shrunken picture of the screen and gets text back — the
previous wording, "each frame goes through on-device text recognition", was
false under this design and is gone. There is no setting that changes it, and
the switch that used to promise one ("Use the cloud for replies") is gone too,
because nothing in the code read it.

The memory question is still open and is stranger than it looked. Over the 30
screens in `Bar/screen-context/`, in one process, `VNDetectTextRectanglesRequest`
alone peaks at 9.9-11.3 MB on the iOS Simulator and 66.7-72.6 MB on macOS 26.5.1,
and `.fast` recognition at 18.1-22.9 MB against 84.6-95.1 MB. Both platforms ship
the same Vision model assets and both report the same compute device for these
two requests: `[cpu]`. The gap is where the kernel charges the memory, not what
runs — macOS puts ~63 MB on the footprint ledger jetsam reads, while the iOS
build maps ~11 MB file-backed and charges the ledger ~5 MB. Which of those a
phone does is unknown, and there is no device measurement here.
`Bar/screen-context/harness/run-memory.sh` re-takes all of it.

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
| `MockScreenContext` | **Reading a frame is done and measured** — `RoutedScreenReader`, scored against `Bar/screen-context/`. **Getting** one is not. ScreenCaptureKit is `iOS 27.0+` and absent from the iOS 26.2 SDK this project compiles against. The ReplayKit route is built except for the read: the app hosts `RPSystemBroadcastPickerView` so a user can start a broadcast, `AIKeyboardBroadcast` fingerprints every sampled frame and publishes a `CaptureStatus` page, and `ScreenContextSession` consumes that page — the strip and the app screen render no session, starting, watching, a reading, paused and stopped-unexpectedly from it, and Reply raises `intent.readNow` and waits for a reading the freshness gate accepts. The read is there too: a tap makes `AIKeyboardBroadcast` encode one frame and call `CloudScreenReader` on its own serial queue, then publish the text with the identity of the frame it read. **And none of it has ever run**: the iOS Simulator ships no `replayd`, so no broadcast session starts here and `SampleHandler` has never been called. The scripted sample stays behind a button on the Screen Context screen, labelled as a sample, and yields to a real session the moment one appears. `ScreenContextSession.submit(_:appName:appIcon:)` is the in-app seam. |
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

The capture channel rides the same container and is proved the same way, by
`Scripts/prove-capture-channel.sh`. Two fixed-layout pages are `mmap`'d
`MAP_SHARED` behind a seqlock — 256 bytes of status from the capture process,
64 bytes of intent back from the keyboard — and one JSON file carries the
reading. **Only text and hashes cross.** The pages hold timestamps, counters and
a 32-byte SHA-256 of a greyscale reduction; `ScreenReadingRecord` has a sender, a
message and a language and no field an image could go in. The script drives two
real processes and takes its verdict from the keyboard extension's own log
lines: it read a session identifier and a live sequence of frame identities
written by another process, found a reading of the frame on screen offerable,
and retired it the moment that frame changed. What it explicitly does **not**
prove is that the producing process is the broadcast extension. There is no
`replayd` here, so the producer in that run is the app driving the same writer
over synthetic frames, and ReplayKit's half is untested on any hardware.

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

Four tests live in `AIKeyboardUITests/DemoWalkthroughTests.swift`, and 229 unit
tests in `AIKeyboardCoreTests`. The two cross-process suites,
`AppGroupCrossProcessTests` and `CaptureChannelCrossProcessTests`, are driven by
the `Scripts/prove-*.sh` scripts rather than judged by their own assertions; see
`.claude/docs/testing.md`.

## Not built

- Anything about ReplayKit that a device would settle: that frames arrive, in
  what pixel format and size, whether the extension fits its ~50 MB cap, and
  whether the picker's button works from inside a keyboard extension
- The keyboard extension runs in a real text field — `Scripts/prove-app-group.sh`
  drives it — but only far enough to prove it reads shared settings; the panels
  are still exercised through the in-app playground
- Landscape, iPad layouts, Dynamic Type above the default size
- Real StoreKit, accounts, or any backend
