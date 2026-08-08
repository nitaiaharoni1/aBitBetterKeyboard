# Screen capture: where the reading happens

Design for turning `ScreenContextSession.submit(_:appName:appIcon:)` from a seam into
a live pipeline. Written 2026-08-08 against Xcode 26.2 (17C52), iPhoneOS26.2.sdk,
macOS 26.5.1 (25F80). Revised the same day after an independent review found the
memory argument inverted and the privacy argument missing.

Three rules this document holds itself to, because the first version broke all three:

1. **Every number says which deployment produced it.** `iOS Simulator`, `macOS`, or
   `iOS device`. There is no such thing as an unlabelled megabyte here: the same code
   over the same 30 images differs by 8x between the two deployments this machine can
   reach.
2. **No device number appears anywhere, because none exists.** The paired iPhone is
   offline. Everything that needs a device is labelled **unproven** and named as such.
3. **Every API claim is quoted from a header on this machine, with the path**, or
   marked **unverified** with the experiment that would settle it.

The probe behind §2 is `Bar/screen-context/harness/memory.swift`, driven by
`Bar/screen-context/harness/run-memory.sh`. Both exist in the repo. The script fails
rather than skips when it cannot measure, in the manner of `Scripts/prove-app-group.sh`.

---

## 0. Evidence status, up front

| Section | Status |
|---|---|
| §1 recommendation | **PROVISIONAL.** Rests on §2, which has no device measurement. |
| §2 memory | **PROVISIONAL.** Measured on two deployments, neither of which is an iPhone. |
| §3 data flow, §4 files | Design. Sized by §2, so provisional with it. |
| §5 privacy | Decided. Does not depend on §2 except to *raise* the stakes. |
| §6 freshness | Design. Independent of §2. |
| §7 which app is on screen | **Verified** against `RPBroadcastExtension.h`. |
| §8 teardown | **Verified** against `RPError.h` and `RPBroadcast.h`. |

---

## 1. Recommendation

**Option (c): the broadcast extension is a shutter with a phone line. It reads nothing
itself.** It throttles 60 fps down to a 4 Hz fingerprint, keeps exactly one reusable
downscaled buffer, and — only when the user taps Reply — encodes one JPEG and hands it
to `CloudScreenReader` over `BackendTransport`. Only text crosses the App Group:
a `ScreenReadingRecord` (sender, message, language) and a fixed-layout `CaptureStatus`
page (heartbeat, 64-bit frame hash, counters).

**Screen reading in the shipping capture flow is cloud-only.** That is the conclusion the
evidence supports, and it is not a preference. Three facts force it:

1. **Every process that could read the screen while the user is in another app is
   memory-capped.** The broadcast upload extension at ~50 MB and the keyboard extension
   at ~48 MB. The containing app has no such cap and is not running when the user is in
   WhatsApp, so it is not a candidate. (Neither cap is in any header on this machine;
   see §2.1 for exactly what each one rests on.)
2. **Vision's text recogniser costs more than that in every ANE-equipped measurement
   available.** On macOS 26.5.1, which maps `AppleNeuralEngine.framework`,
   `ANEServices.framework` and `ANECompiler.framework`, peak physical footprint over the
   30 bar screens in one process is **199.8 MB** at `.accurate` and **84.7 MB** at
   `.fast`. Even `VNDetectTextRectanglesRequest` on its own — the language-agnostic shape
   detector that `VisionScreenReader`'s whole routing gate depends on — peaks at
   **67.9 MB**. Nothing in the Vision text stack fits in 48 MB on that deployment.
3. **The simulator is the optimistic deployment, not the pessimistic one.** The iOS
   Simulator maps *no* ANE framework (the probe checks and reports this), and on it
   `.fast` peaks at 18.1 MB, which would fit. That number is the reason the previous
   version of this document kept an on-device escape hatch. It is not evidence about a
   phone: **a physical iPhone is an ANE configuration**, so the only ANE-equipped
   measurement obtainable here is 4.7x *higher* than the simulator's, not lower. The
   previous version's risk register said device numbers "could be lower again"; that
   inference is backwards and the escape hatch built on it has been deleted.

**Resolution is not a knob.** At 301x655 — 1/16 of the original pixel count — `.accurate`
still peaks at 171.7 MB (macOS) / 157.3 MB (iOS Simulator) and `.fast` at 71.5 MB
(macOS). The cost is model weights, not activations, and no downscale reaches it.

The accuracy case for on-device reading has also collapsed independently of memory.
`.claude/CLAUDE.md` records that on iOS, routing through Vision scores *worse* than
asking the cloud: sender 26/30 vs 29/30, exact message 16/30 vs 19/30. So the on-device
path would cost memory it does not have, to buy accuracy it does not deliver. The only
thing it buys is privacy, and §5 is where that is paid for instead.

`VisionScreenReader` is not deleted. It stays as the bar-scored reference and as the
in-app playground path, where the containing app is frontmost and has no extension cap.

**What would reverse this, and it requires the device.** Run
`Bar/screen-context/harness/memory.swift` as a device unit test (it compiles for
`arm64-apple-ios` unchanged and reports `deployment = iOS device`). If peak footprint for
`.fast` + rectangles over all 30 images comes in under ~30 MB on an iPhone, an on-device
path is affordable and §5.4 is the checklist for putting it back. Anywhere near the macOS
figure confirms this design. Nothing short of that measurement moves it — in particular,
no simulator run does, and that is the whole lesson of this revision.

---

## 2. Memory budget, with numbers

> **PROVISIONAL.** Every number in this section came from an iOS Simulator or from macOS.
> There is no device measurement in this document and the paired iPhone is offline.

### 2.1 The ceilings

Neither cap is in a header. I grepped `ReplayKit.framework/Headers/` and
`UIKit.framework/Headers/UIInputViewController.h` in `iPhoneOS26.2.sdk`; the strings
"memory limit", "48", "50 MB" and "jetsam" do not appear.

| Process | Cap | What it rests on |
|---|---|---|
| Broadcast upload extension | **~50 MB** | Apple's stated guidance from the ReplayKit sessions, universally reproduced, and the jetsam behaviour in the forum threads `.claude/docs/replaykit-contract.md` cites. Unverified on device here (R2). |
| Keyboard extension | **~48 MB** | Reported by the independent review that produced this revision, 2026-08-08. Not re-derived here and not in any header. Unverified on device here (R2b). |
| Containing app | none | But it is not running when the user is in WhatsApp, so it cannot be the reader in the capture flow. It *is* the reader in the in-app playground. |

The two caps are close enough that they do not change any decision below: both are under
50 MB, and every Vision configuration measured on an ANE deployment is over 67 MB.

### 2.2 Frame arithmetic at 1206x2622

Arithmetic, not measurement. 3,162,132 pixels. Two candidate delivery formats, because
the format ReplayKit hands us is unverified (R1):

| Format | Bytes | MiB |
|---|---|---|
| BGRA8888, rows padded 4824 -> 4864 | 4864 x 2622 = 12,753,408 | **12.2** |
| 420YpCbCr8BiPlanar, rows padded to 1216 | 3,188,352 (Y) + 1,594,176 (CbCr) | **4.6** |

Design for the BGRA case; the 420f case is 7.6 MiB of free headroom if we get it.

Downscale destinations, preallocated once and overwritten in place: 804x1748 (2/3) at
3264 padded row bytes is **5.4 MiB**; 603x1311 (1/2) at 2432 is **3.0 MiB**.

JPEG at q0.70 over all 30 images in `Bar/screen-context/images/` (Pillow 11.3.0, LANCZOS
resample, **macOS host** — CoreGraphics will differ slightly):

| Size | median KB | p90 KB | max KB |
|---|---|---|---|
| 1206x2622 | 176 | 254 | 276 |
| 804x1748 | 96 | 142 | 151 |
| 603x1311 | **66** | **98** | **104** |

Fingerprint thumbnail: 32x64 greyscale = 2,048 bytes. Negligible.

### 2.3 Vision, measured on two deployments, neither of them a phone

`Bar/screen-context/harness/run-memory.sh`. Physical footprint via
`task_info(mach_task_self_, TASK_VM_INFO)` — the same number jetsam reads — sampled after
every image, across **all 30 bar screens in one long-lived process**, one image alive at a
time. One reused request object per process, which is the shape a long-lived extension
would have.

**Peak** is the number that decides the design, because an extension dies at its ceiling
rather than degrading. Base footprint is 2.3-2.4 MB (macOS) and 10.3-11.0 MB (iOS
Simulator); the tables are absolute peaks, so subtract the base for a delta.

| Configuration, 1206x2622 | iOS Simulator 26.2, arm64 — peak MB | macOS 26.5.1 — peak MB |
|---|---|---|
| decode only (the floor) | 10.3 | 4.5 |
| decode + JPEG encode q0.70 | 10.5 | 4.2 |
| `VNDetectTextRectanglesRequest` alone | 10.3 / 11.1 / 10.4 | 67.9 / 66.7 / 69.2 |
| `.fast` + rectangles | 18.1 / 22.8 / 22.9 | 84.7 / 91.1 / 95.1 |
| `.accurate` + rectangles | 174.8 / 174.8 / 176.5 | 194.1 / 198.2 / 206.9 |
| `.accurate`, no language correction, pinned `en-US`, no auto-detect | 100.4 | 111.8 |

Three runs per cell where three were taken. Spread is a few MB; nothing here is inside the
noise floor, and nothing here is close to 48 MB except on the deployment with no ANE.

Resolution sweep, same probe, same 30 images:

| Configuration | scale 1.0 (1206x2622) | scale 0.5 (603x1311) | scale 0.25 (301x655) |
|---|---|---|---|
| `.fast`, iOS Simulator | 18.1 | 19.7 | 19.9 |
| `.fast`, macOS | 84.7 | 73.3 | 71.5 |
| `.accurate`, iOS Simulator | 174.8 | 177.8 | 157.3 |
| `.accurate`, macOS | 199.8 | 184.5 | 171.7 |

Four things this says, and they decide the architecture:

1. **The ANE frameworks are the variable.** The probe enumerates loaded images and
   reports which Neural Engine frameworks are mapped. macOS maps `ANECompiler`,
   `ANEServices`, `AppleNeuralEngine` and `Espresso`. The iOS Simulator maps `Espresso`
   only. `run-memory.sh` asserts this both ways and fails if it ever stops being true,
   because it is the control that makes the two columns mean anything.
2. **Resolution is not a knob.** 1/16 of the pixels moves `.accurate` by 10-14% and
   `.fast` on macOS by 16%. Neither crosses 48 MB from the wrong side. The previous
   version's "halving resolution buys 14 MB" was a single-image reading and is not a
   finding; over 30 images at half scale `.accurate` is *higher* in the simulator, not
   lower.
3. **It does not come back.** Simulator `.accurate` climbs 89.4 (image 1) -> 116.9 ->
   126.8 -> 141.5 (image 10) -> 162.4 (image 20) -> 173.9 (image 28) and finishes at
   154.2 after a drained `autoreleasepool`. It never returns near the 10.4 MB base. The
   independent review's probe did not reproduce this climb (it saw 84 -> 104 over the
   same 30 screens). Two independent probes disagreeing on the *shape* of the climb is
   worth knowing; what both agree on, and what the design depends on, is that peak is
   multiples of the ceiling and the process never returns to base.
4. **The cheap half is not cheap where it counts.** The previous version rested an
   on-device path on `VNDetectTextRectanglesRequest` costing +3.1 MB. That is a
   simulator number. On the ANE deployment the same request peaks at 67.9 MB — over the
   cap on its own, before any recognition runs. The routing gate that
   `VisionScreenReader` is built on does not fit either.

### 2.4 The extension's budget, assembled — and what is still unmeasured

> **This total is conditional.** Two of six lines are unmeasured estimates, and they are
> the two largest after the frame itself. Phase 3 exists to measure them, and the design
> does not proceed past Phase 3 without them.

Recommended configuration: 603x1311 downscale, cloud read, no Vision anywhere.

| Line | MB | Status |
|---|---|---|
| Baseline: ReplayKit + Foundation + `AIKeyboardShared`, no UIKit/SwiftUI | ~20 | **est., unmeasured.** Needs a device: the iOS 26.2 simulator runtime ships no `replayd`, so no broadcast extension process exists to weigh. |
| ReplayKit's in-flight frame, mapped BGRA | 12.2 | arithmetic (§2.2), format unverified (R1) |
| Downscale destination, preallocated and reused | 3.0 | arithmetic (§2.2) |
| Decode + downscale + JPEG encode, transient | **< 0.2** | **measured**, iOS Simulator: over all 30 images at scale 0.5 the process peaked 0.1-0.2 MB above its 10.4 MB base. Bare CLI process, PNG source rather than a `CVPixelBuffer`, so treat as a floor. |
| JPEG bytes held for the request | 0.10 | arithmetic (§2.2) |
| `URLSession` + TLS during a read | 4-8 | **est., unmeasured** (R7) |
| **Total** | **~39-44 MB against a ~50 MB cap** | **conditional on the two estimates above** |

The honest reading: the only line this document has measured is the one that turned out
to cost nothing. The frame and the buffer are arithmetic. The baseline and the network
stack are guesses, and together they are 24-28 MB of a 39-44 MB total. A design whose
headroom against a ~50 MB cap is 6-11 MB, and 24-28 MB of whose total is guessed, is not
proven to fit. **Phase 3 is the
gate**: build the shutter with no reading in it, run it on a device against WhatsApp for
ten minutes with a memory graph attached, and read the real baseline. If baseline + frame
+ downscale exceeds 30 MB, there is no room for TLS and the design changes before any
reading code is written.

Two consequences that must be in the code, not in a comment:

- **Never link `AIKeyboardCore` into the broadcast extension.** `Models.swift`,
  `Theme.swift`, `KeyboardController.swift`, `Feedback.swift` and every panel import
  SwiftUI or UIKit, and `SharedStore` reaches `Feedback`, so linking the package drags
  UIKit and SwiftUI into a ~50 MB process for nothing. §4 splits out `AIKeyboardShared`.
- **The extension polices its own footprint.** `MemoryGovernor.footprintMB()` wraps the
  same `task_info(TASK_VM_INFO)` call `memory.swift` uses. Refuse to start a read above a
  watermark and publish `CaptureStatus.degraded` instead. The watermark cannot be set
  until Phase 3 gives a real baseline; 35 MB is the placeholder and it is a placeholder.
  A visible degraded state beats a jetsam kill, because a jetsam kill ends the broadcast
  and only the user can restart it.

---

## 3. Data flow, end to end

Three processes, one shared container, no pixels between them.

```
  WhatsApp on screen
        |
        | 60 fps CMSampleBuffer
        v
  +-------------------------------------------------+
  | AIKeyboardBroadcast   (RPBroadcastSampleHandler) |
  |                                                  |
  |  processSampleBuffer     -- never blocks --      |
  |    -> monotonic gate: drop unless >= 250 ms      |  ~microseconds, 56 of 60 frames
  |    -> lock base addr, scale to 32x64 grey        |  2 KB
  |    -> FrameFingerprint: dHash64 + changeScore    |
  |    -> publish hash + sampledAt to status.bin     |  every sampled frame, always
  |    -> CaptureLoop.shouldRead(...) ?              |
  |         no  -> return                            |
  |         yes -> scale to 603x1311 (reused buf)    |  3.0 MB, overwritten in place
  |                encode JPEG q0.70                 |  ~66 KB median
  |                hand bytes to the read queue      |  <-- returns here
  |                                                  |
  |  read queue (serial, one in flight)              |
  |    -> CloudScreenReader.read(...)                |  ~5.3 s median
  |    -> zero + release the JPEG                    |
  |    -> write ScreenReadingRecord                  |  text only
  +--------------------+-----------------------------+
                       |
        group.com.nitai.aikeyboard container
        +-- channel/status.bin    fixed 128 B, mmap MAP_SHARED, 1 Hz + every sample
        +-- channel/intent.bin    fixed  64 B, mmap MAP_SHARED
        +-- channel/reading.json  text only, atomic write, rare
                       |
  +--------------------+-----------------------------+
  | AIKeyboardExtension  (the keyboard)              |
  |                                                  |
  |  viewDidAppear  -> intent.keyboardVisible = 1    |
  |  4 Hz while visible: read status.bin             |
  |    -> the five-condition freshness gate, §6      |
  |    -> ScreenContextSession.state                 |
  |  Reply tapped -> intent.readNow = seq+1          |
  |               -> await reading.json, seq match   |
  +--------------------------------------------------+

  +--------------------------------------------------+
  | AIKeyboard  (the app)                            |
  |  RPSystemBroadcastPickerView to start            |
  |  Screen Context screen reads status.bin          |
  |  owns the read budget and the history            |
  +--------------------------------------------------+
```

### 3.1 The read is off the delivery path, and that is load-bearing

`processSampleBuffer(_:with:)` must return promptly. It is the 60 fps delivery callback;
a 5.3 s cloud round trip inside it stalls delivery for 5.3 s, and while delivery is
stalled the extension observes no new frames — which is exactly the freshness hole §6
closes. So:

- `processSampleBuffer` does the throttle, the fingerprint, the status write, the
  decision, and (when the decision is yes) the downscale and the JPEG encode. All of that
  is CPU-bounded and measured at under 0.2 MB above process base in the iOS Simulator
  (§2.4). Then it returns.
- The cloud call runs on a serial `DispatchQueue`, one read in flight at a time. A second
  request while one is in flight is refused and counted, never queued.
- Because delivery keeps running during the read, the fingerprint keeps advancing, and
  §6's condition 5 can be satisfied within one 250 ms sample of the read completing.

This is the single most important structural detail in §3 and it is why §6 works at all.

### 3.2 Why mmap and not `UserDefaults`

`SharedStore` uses `UserDefaults(suiteName:)`, which is right for settings and wrong for
this. Cross-process `UserDefaults` change notification has not been reliable since iOS 8,
and `CFPreferences` synchronises opportunistically — a 1 Hz heartbeat read through it
would be neither prompt nor trustworthy. Two fixed-layout files, `open(O_RDWR)` once and
`mmap(MAP_SHARED)`, give a memcpy write and a load read with no allocation, no atomic
rename, and no notification machinery. Torn reads are handled with a seqlock: write an odd
sequence, write the body, write the next even sequence; the reader retries while the two
sequences disagree or the low bit is set.

Both pages are timestamps, counters and a 64-bit hash. Both stay at the container default
`.completeUntilFirstUserAuthentication` on purpose: an mmap'd file marked `.complete`
becomes unreadable when the device locks, and touching it then is a SIGBUS, not an error
return.

Darwin notifications (`CFNotificationCenterGetDarwinNotifyCenter`) are deliberately **not**
in the design. Polling at 4 Hz costs a page load and adds at most 250 ms to a 5.3 s
operation. Adding a notification path adds a runloop dependency and a dropped-message
failure mode for no user-visible gain. If latency ever matters, add
`com.nitai.aikeyboard.capture.reading-ready` as an optimisation over the top of the poll,
never as a replacement for it.

### 3.3 The trigger: one trigger, and it is a tap

Frames arrive at up to 60/s. `processSampleBuffer` does nothing but fingerprint 56 of
every 60. A **read** — the 5.3 s, costs-money, leaves-the-device operation — fires on
exactly one condition:

**T1, explicit.** The user tapped Reply. `intent.readNow` carries a monotonically
increasing request sequence; the extension reads the next settled frame and stamps the
record with that sequence.

Subject to four refusals, all of which publish a counter rather than failing silently:

- Full Access is off, so the keyboard cannot reach the container at all (§3.5).
- `MemoryGovernor` is above the watermark.
- A read is already in flight.
- The session or daily read budget is exhausted.

Plus one that is a privacy rule rather than a resource rule, and belongs in code next to
the others: **never fire a read while the focused field is a secure text entry field.**
`UITextDocumentProxy` conforms to `UIKeyInput` (`UIInputViewController.h:20`), which
conforms to `UITextInputTraits` (`UITextInput.h:24`), which declares
`isSecureTextEntry` (`UITextInputTraits.h:257`). Whether a host app reliably propagates
that trait through the proxy is **unverified** and is R14; the guard is cheap and belongs
there regardless of how often it fires.

**There is no speculative trigger.** The previous version had one — T2, default on, firing
whenever the keyboard was visible and the screen had settled. It is deleted. §5.1 is the
argument, and it is not a close call.

Neither trigger ever fires on frame arrival, screen change alone, or a timer, because
there is only one trigger and it is a tap.

### 3.4 What the keyboard shows before the tap

Deleting T2 costs a real thing: the strip has nothing to show until the user asks. That is
the correct trade and the copy should own it. Before a tap the strip reads **"Reply can
read this screen"** with the red capture dot — an offer, not a claim. After a tap it shows
the loading state, then the sender. It never shows a message the user did not ask for,
because it never has one.

### 3.5 Full Access

The keyboard extension gets the App Group container only with Full Access — that is
already the reason `RequestsOpenAccess` is `true`. The broadcast extension is not a
keyboard and gets the container unconditionally. So the *capture* half works without Full
Access and the *consuming* half does not, which means screen context is Full-Access-only
end to end. `SharedStore.storage == .processLocal` in the keyboard is the exact signal;
`hasFullAccess` (verified, `UIInputViewController.h:56`, `API_AVAILABLE(ios(11.0))`) is
the one to show the user a reason with.

### 3.6 One bug this uncovered, now fixed

The first version of this document found that `KeyboardController.swift:132` called
`BackendTransport.configured()` whose default was `UserDefaults.standard` — the
extension's own private store — so the backend URL the user set in the app never arrived
and the cloud path was silently unconfigured. That is fixed: `configured(defaults:)` now
defaults to `SharedStore.shared.userDefaults`
(`CloudIntelligence.swift:262-269`), and `AIKeyboardCoreTests/BackendTransportSuiteTests.swift`
pins it. The broadcast extension inherits the fix by calling the same default. Nothing to
do here beyond not regressing it.

---

## 4. Files

### Already created by this document

| Path | Contents |
|---|---|
| `Bar/screen-context/harness/memory.swift` | The §2.3 probe. `phys_footprint` via `task_info(TASK_VM_INFO)` over all 30 bar images in one process, one image alive at a time, one reused request. Reports its own deployment and which ANE frameworks are mapped. Exits non-zero on a missing image, a failed Vision call or a `task_info` that will not answer: a probe that cannot measure prints no number. Compiles unchanged for `arm64-apple-ios`, which is how it becomes the device measurement §1 asks for. |
| `Bar/screen-context/harness/run-memory.sh` | Builds both deployments, requires a booted simulator, asserts that macOS maps `AppleNeuralEngine` and the simulator does not, and prints the labelled peak table. Fails rather than skips at every step. `SCALES="1.0 0.5 0.25"` runs the resolution sweep, `CONFIGS=fast` narrows it. Verified to fail, not skip: an absent simulator exits 1, an absent image directory exits 3. |

### Create

| Path | Contents |
|---|---|
| `AIKeyboardBroadcast/Info.plist` | `NSExtensionPointIdentifier = com.apple.broadcast-services-upload`, `RPBroadcastProcessMode = RPBroadcastProcessModeSampleBuffer`, `NSExtensionPrincipalClass = $(PRODUCT_MODULE_NAME).SampleHandler`. Verified against Xcode's own template at `iPhoneOS.platform/.../Broadcast Upload Extension.xctemplate/TemplateInfo.plist`. Needs a `membershipExceptions` entry, as `AIKeyboardExtension/Info.plist` has. |
| `AIKeyboardBroadcast/AIKeyboardBroadcast.entitlements` | `com.apple.security.application-groups` = `group.com.nitai.aikeyboard` |
| `AIKeyboardBroadcast/SampleHandler.swift` | `final class SampleHandler: RPBroadcastSampleHandler`. Overrides `broadcastStarted(withSetupInfo:)`, `broadcastPaused()`, `broadcastResumed()`, `broadcastFinished()`, `broadcastAnnotatedWithApplicationInfo(_:)`, `processSampleBuffer(_:with:)`. Owns a `CaptureLoop`, the heartbeat timer and the serial read queue, and nothing else. Under 150 lines. |
| `AIKeyboardBroadcast/CaptureLoop.swift` | `final class CaptureLoop` — the throttle/settle/budget state machine. Its API takes `(hash: UInt64, changeScore: Double, now: ContinuousClock.Instant, intent: CaptureIntent)` and returns `CaptureDecision`. No ReplayKit or CoreVideo types cross its boundary, so every trigger rule is unit-testable off-device. |
| `AIKeyboardBroadcast/FrameScaler.swift` | `struct FrameScaler` — vImage. One preallocated `vImage_Buffer` per output size, created at `broadcastStarted` and reused. Scales planes *before* colour conversion when the source is 420f, so no full-size ARGB intermediate is ever allocated. |
| `AIKeyboardBroadcast/MemoryGovernor.swift` | `enum MemoryGovernor { static func footprintMB() -> Double }` over `task_info(TASK_VM_INFO)`, plus the read watermark. Share the implementation with `memory.swift` by eye, not by import: the probe must stay outside every target. |
| `Packages/AIKeyboardCore/Sources/AIKeyboardShared/CaptureChannel.swift` | `enum CaptureChannel` (container URLs), `struct CaptureStatus` and `struct CaptureIntent` (fixed C layouts), `final class SharedPage<T>` (the mmap + seqlock wrapper). `CaptureStatus` carries `currentFrameHash` **and** `currentFrameSampledAt` **and** `lastFrameAt` **and** `paused` — §6 needs all four and a design that ships three of them has the stale-reading bug. |
| `Packages/AIKeyboardCore/Sources/AIKeyboardShared/FrameFingerprint.swift` | `struct FrameFingerprint { let hash: UInt64; let changeScore: Double }` and the 32x64 greyscale reduction, with the crop bands. |
| `Packages/AIKeyboardCore/Sources/AIKeyboardShared/ScreenReadingRecord.swift` | `struct ScreenReadingRecord: Codable, Sendable` — `sessionID`, `requestSequence`, `frameHash`, `capturedAt`, `readAt`, `provenance`, and the `ScreenReading` fields. Text only, by construction. |
| `Packages/AIKeyboardCore/Sources/AIKeyboardShared/ScreenContextEndReason.swift` | `enum ScreenContextEndReason: UInt8` — `.userStopped`, `.deviceLocked`, `.phoneCall`, `.interrupted`, `.contentResized`, `.carPlay`, `.overBudget`, `.lost`. The middle five map from `RPRecordingErrorCode` (verified, `RPError.h`); `.lost` is the inferred one, from a stale heartbeat with no recorded end. |

### Modify

| Path | Change |
|---|---|
| `Packages/AIKeyboardCore/Package.swift` | Add `.library(name: "AIKeyboardShared", ...)` and `.target(name: "AIKeyboardShared")`; `AIKeyboardCore` gains it as a dependency. One `@_exported import AIKeyboardShared` keeps every existing call site compiling; if that misbehaves, adding explicit imports is mechanical. |
| `.../AIKeyboardCore/Models.swift` | Move `KeyboardLanguage`, `TextScript`, `ScreenContext`, `ScreenContextState` into `AIKeyboardShared`. The file's only SwiftUI use is `KeyboardLanguage.layoutDirection` (line 40); it becomes a one-line extension left behind in `AIKeyboardCore`. **Also fix the doc comment at lines 149-151** (§5.2). |
| `.../AIKeyboardCore/ScreenReader.swift`, `CloudScreenReader.swift`, `LanguageDetector.swift` | Move to `AIKeyboardShared` unchanged. All three are already Foundation/CoreGraphics-only. |
| `.../AIKeyboardCore/CloudIntelligence.swift` | Split: `CloudField`, `CloudImage`, `CloudRequest`, `CloudTransport`, `BackendTransport` move to `AIKeyboardShared`; `CloudIntelligence` itself stays. The App Group default on `configured(defaults:)` is already in place; keep it through the move and keep `BackendTransportSuiteTests` passing. |
| `.../AIKeyboardCore/ScreenContextSession.swift` | The scripted timeline goes. It becomes a consumer: poll `CaptureStatus` at 4 Hz while the keyboard is visible, apply the §6 gate, publish `.off/.starting/.watching/.ready/.ended`. `submit(_:appName:appIcon:)` stays for the in-app playground and the UI tests, and is the only path that still runs `RoutedScreenReader` locally. Fix the doc comment at lines 90-96, which promises the frame never leaves. |
| `.../AIKeyboardCore/Models.swift` (`ScreenContextState`) | Add `case ended(ScreenContextEndReason)`. `isLive` stays false for it. |
| `.../AIKeyboardCore/ScreenContextStrip.swift` | Render `.ended` with the reason and the restart affordance. Render the pre-tap offer state (§3.4). Stop labelling the app (§7). `ScreenContext.appName`/`appIcon` become optional. |
| `.../AIKeyboardCore/KeyboardController.swift` | `requestScreenRead()` bumps `intent.readNow` after checking `textDocumentProxy.isSecureTextEntry`; Reply awaits a record with a matching sequence, with a 12 s timeout mapping to a new `AIActionError` case. `viewDidAppear`/`viewWillDisappear` drive `intent.keyboardVisible`. |
| `.../AIKeyboardCore/SharedStore.swift` | Add `screenContextDailyReadBudget: Int`. **Do not** add a speculative-reads flag. Fix the doc comment at line 144, which says only text leaves the device (§5.2). |
| `AIKeyboard/Main/ScreenContextView.swift` | Rewrite step 2 at line 205 and check step 3 at line 210 (§5.2). Host `RPSystemBroadcastPickerView` with `preferredExtension` set to the broadcast bundle ID and `showsMicrophoneButton = false` (both verified, `RPBroadcast.h`). Show live `CaptureStatus`, the budget, and the restart button. |
| `AIKeyboard.xcodeproj/project.pbxproj` | New target. Files inside `AIKeyboardBroadcast/` are picked up by `PBXFileSystemSynchronizedRootGroup` once the group exists, but the target itself is a real `.pbxproj` edit. |
| `Scripts/prove-app-group.sh` | Add check 5: two processes mmap `channel/status.bin` and each observes the other's write. |
| `README.md` | **Add** a paragraph; do not replace the existing one (§5.3). |

---

## 5. Privacy

### 5.1 Why there is no speculative read

The previous version of this document contained a contradiction it did not notice.
§7 concludes, from the header text, that this design **cannot know which app is on
screen**. The previous §3.2 then fired a speculative cloud upload whenever the keyboard
was visible and the picture had settled, **default on**. Put together: the product would
upload screenshots of whatever the user happened to have open — a bank, a password
manager, a health app, a photo of a document — to a backend, with no user action, and by
its own analysis could not know it was doing so, could not tell the user, and could not
log it accurately afterwards.

Cloud-only reading makes that strictly worse, not better. Under the previous version some
reads were supposed to stay on device. Now **every read leaves the device**, so every
speculative read is an upload.

The obvious narrowing does not work, and the reason is worth writing down because someone
will propose it again. "Only fire when our keyboard is visible" sounds like it restricts
capture to conversations. It does not: a keyboard is up in a password field, in a banking
transfer form, in a medical intake form, in a 2FA prompt. Keyboard-visible is not a
proxy for *safe to upload*; if anything it correlates with the most sensitive screens on
the phone.

And the narrowing that *would* work is circular. To decide whether it is safe to upload
this screen, you would have to know what is on it. Knowing what is on it is the read.
There is no cheaper signal available on this deployment:

- `broadcastAnnotatedWithApplicationInfo:` gives the **first** app only, and only from a
  Control Center start (§7, verified). Not a live signal.
- There is no public API on iOS for the frontmost bundle identifier from any extension.
- The 64-bit dHash of a 32x64 greyscale reduction cannot classify a screen.
- Protected content blacking itself out under ReplayKit is **unverified** (R13), so the
  OS cannot be relied on to redact what we failed to exclude.

**So: a frame leaves the device only in direct response to a tap on Reply.** That is the
design, it is not a setting, and there is no toggle that turns it into something else. The
consent model has two layers and both are visible: the user starts the broadcast in
Apple's own picker and iOS shows the red pill for its whole duration (the capture
envelope), and the user taps Reply for each individual upload (the transmission).

If a speculative path is ever proposed again, the bar it has to clear is a *live*,
verified, frontmost-application signal that positively identifies a messaging app — not a
heuristic, not a denylist, and not a screen fingerprint. §7 shows that signal does not
exist on iOS 26.2. Until it does, this section is settled.

### 5.2 The promises in the product, and which ones are now false

The previous version claimed a `README.md` sentence was "already false". That was wrong
on the facts: `README.md` lines 110-121 are accurate today and are the most carefully
measured paragraph in the file. The claim that needs fixing lives in three other places,
and two of them are about to become false for a new reason.

| Where | Text | Status |
|---|---|---|
| `AIKeyboard/Main/ScreenContextView.swift:205` | "Each frame goes through **on-device** text recognition. The frame is overwritten by the next one and never saved." | **False under this design.** The recognition is not on-device. The second sentence stays true and stays. |
| `AIKeyboard/Main/ScreenContextView.swift:210` | "The keyboard receives the recognised message, not an image, and only when you tap Reply." | **True, and it stays true only because T2 is deleted.** This sentence is the reason §5.1 is not a close call: the product already promises it. |
| `Packages/.../SharedStore.swift:144` | "Only the text read off the frame ever leaves the device." | **Already false**, since `CloudScreenReader` existed — it posts a JPEG. Not a README problem; a code-comment problem. |
| `Packages/.../Models.swift:149-151` | "the product promise is that pixels are overwritten and never kept, so the only thing that travels is the text that was read off them" | **Half false.** Overwritten and never kept: true. Only text travels: false. |
| `Packages/.../ScreenContextSession.swift:90-96` | "The frame is read and dropped; only the text survives the call, which is the promise the Screen Context screen makes." | **Half false**, same split. |

The accurate claim, which each clause maps to code:

> The screen is never stored. One frame at a time lives in a single buffer inside the
> capture process and is overwritten by the next; nothing on disk, in the shared
> container, or in a backup ever contains a picture of your screen. A frame leaves the
> device only when you tap Reply, and what comes back is text.

The buffer is a `vImage_Buffer` preallocated at `broadcastStarted`; the container holds
two fixed-layout binary pages and one JSON file whose type has no image field; the frame
leaves only inside `CloudScreenReader.read`, only on the serial read queue, only with a
matching `intent.readNow` sequence.

### 5.3 What the README needs, and what it must keep

`README.md` lines 110-121 stay. They are the on-device/cloud split earned with measured
numbers (30 languages, 100% English recall, 13% Hebrew, the coverage/confidence gate), and
that split is still true of `RoutedScreenReader` and still true of the in-app playground
path, where the containing app holds the frame and no extension cap applies. Replacing
them with a vaguer sentence would trade measured content for nothing.

What needs rewriting is the paragraph that follows, lines 123-132, which currently poses
this document's question as open:

> Two things are still open and are being measured rather than argued: whether Vision can
> run at all inside the ~48 MB a keyboard extension gets or the 50 MB a broadcast
> extension gets, and whether the privacy gain of keeping eight English frames on the
> device is worth three points of accuracy. If the answer to the first is no, the second
> is moot and every screen read goes to the cloud.

§2.3 answers the first, on two deployments and not yet on a phone. Lines 123-127 stay as
written; lines 128-132 become:

> The first of those is now measured, though not yet on a phone. Over the 30 screens in
> `Bar/screen-context/`, in one process, peak physical footprint is 199.8 MB at
> `.accurate` and 84.7 MB at `.fast` on macOS 26.5.1 — and even
> `VNDetectTextRectanglesRequest` on its own, the shape detector the routing depends on,
> is 67.9 MB. All three are over both extension budgets. The iOS Simulator is far cheaper
> (174.8 / 18.1 / 10.3 MB) and is not the phone: it maps no Apple Neural Engine framework
> and macOS maps four, so the simulator is the optimistic deployment rather than the
> pessimistic one. Downscaling does not rescue it; 1/16 of the pixels moves `.accurate` by
> 10-14%. So in the ReplayKit capture flow every screen read goes to the cloud, English
> included, and it goes only when you tap Reply. `Bar/screen-context/harness/run-memory.sh`
> re-takes those numbers. A device measurement would settle it and there is not one yet.

That keeps every measured claim the README already earns, answers the question it already
asks, and labels the deployment behind each number. The mock-to-real table's
`MockScreenContext` row also needs the ReplayKit route marked as designed-but-unbuilt
rather than absent.

### 5.4 What the App Group actually holds

- `channel/status.bin`, 128 bytes: session UUID, heartbeat, last frame time, current
  frame hash and the time it was sampled, paused flag, frames seen, reads fired, reads
  refused by reason, last end reason, degraded flag.
- `channel/intent.bin`, 64 bytes: keyboard-visible flag, read request sequence.
- `channel/reading.json`: `ScreenReadingRecord`. Sender, message, language, hashes,
  timestamps. Deleted on `broadcastFinished()` and on session start.

The one thing worth arguing about is the `dHash64`. It is a 64-bit difference hash of a
32x64 greyscale reduction of the conversation area. 2,048 samples collapsed to 64 bits
cannot recover glyphs, and it is not a hash *of* the text — but it is a per-screen
identifier, so two devices reading the same screen produce the same value. It never leaves
the device and no reason to send it exists. Say so in the code.

### 5.5 The frame is cropped before it is hashed, and that matters

The fingerprint is taken over the frame with two bands removed: the status bar (top ~6.5%,
matching `VisionScreenReader.Band.statusBar` at y >= 0.935) and the bottom 45% where our
own keyboard sits. Without the first, the clock ticking over invalidates every reading once
a minute. Without the second, our own suggestion bar redrawing invalidates readings
constantly.

### 5.6 Option (b), analysed as asked, and now dead twice over

Option (b) — the extension stashes a downscaled frame, the keyboard reads it on demand —
puts a JPEG of a private conversation into the App Group container. Six things would have
to be true for that to be defensible:

1. **Written with `FileProtectionType.complete`.** The container default is
   `.completeUntilFirstUserAuthentication`, which means the file is readable by anything
   holding the container on a device that has been unlocked once since boot, including a
   forensic extraction of a locked-but-warm phone.
2. **Exactly one slot, `O_TRUNC` in place, never a rotating name.** A `frame-0001.jpg`
   scheme accumulates conversations on the filesystem.
3. **Three independent deletes**: producer TTL (2 s), producer on `broadcastFinished()`,
   consumer immediately after reading the bytes. Any one of them is skipped by a crash, so
   all three are needed.
4. **`isExcludedFromBackup`.** App Group containers are backed up by default, so without
   this a screenshot of a private conversation reaches iCloud.
5. **Fixed-size slot, zeroed before unlink.** `unlink` does not erase; APFS blocks survive
   until reused. Zeroing is only meaningful if the slot is a fixed size, which a JPEG is
   not, so the slot has to be padded to a constant.
6. **The privacy copy has to be rewritten** to say a frame sits in the shared container
   for up to two seconds. You cannot keep the sentence and change the behaviour; the
   promise is the product.

So (b) *can* be honest. It is rejected on two independent grounds, either of which is
enough. The only thing (b) buys is letting the keyboard run `RoutedScreenReader`
on-device, and (i) §2.3 measures every Vision configuration above the keyboard
extension's own ~48 MB cap on the ANE deployment, and (ii) `.claude/CLAUDE.md` records
that on iOS the routed path scores *worse* than the cloud on this bar. (b) would pay six
real obligations for a capability that does not fit and would not be better if it did.

If the device measurement in §1 comes back under ~30 MB, ground (i) falls and this section
is the checklist. Ground (ii) still stands and would have to be answered separately.

### 5.7 Two things I did not verify

The README claims protected content blacks itself out under capture. I did not re-verify
that (secure text entry and DRM layers under ReplayKit); it should be checked on device
before the claim ships, and §5.1 explicitly does *not* rely on it. And the model on the
far end of `BackendTransport` sees a screenshot: the retention policy of the backend is a
real part of this privacy story and is outside this document. `BackendTransport` already
sends images to a separate endpoint from text, specifically so the backend can hold them
to a different rule — that endpoint's rule needs to be written down somewhere, and with
reading now cloud-only it is no longer a minor loose end.

---

## 6. Freshness

The scenario to defeat is the one named in the brief: a reading from 40 seconds ago, from
a different conversation, presented as current. Time alone does not catch it — the user can
switch conversations in two seconds. **The rule is content-addressed, with time as a
backstop and an explicit confirmation step.**

A `ScreenReadingRecord` is offerable iff all five hold at the instant the strip renders:

| # | Condition | Catches |
|---|---|---|
| 1 | `now - status.heartbeatAt <= 3 s` | the extension process is dead, including a jetsam kill that fired no callback |
| 2 | `status.paused == 0` and `now - status.lastFrameAt <= 2 s` | the process is alive but frames have stopped: `broadcastPaused()`, a stalled delivery path, a wedged handler |
| 3 | `status.currentFrameSampledAt >= record.readAt` | **the reading has been confirmed against a frame observed after it completed** |
| 4 | `record.frameHash == status.currentFrameHash` | the user scrolled, switched conversation, switched app, or a new message arrived |
| 5 | `now - record.capturedAt <= 20 s` and `record.sessionID == status.sessionID` | intent moved even though the pixels did not; the broadcast was restarted since the reading |

Fail 1 and the strip renders `.ended`. Fail 2 and it renders `.paused`. Fail 3 and it
renders the loading state, because the reading is not stale, it is merely unconfirmed.
Fail 4 or 5 and it renders the pre-tap offer. **The strip has no stale-but-shown state at
all.**

### 6.1 Condition 3 is the one this revision adds, and it is the one that mattered

Conditions 1, 4 and 5 were in the previous version and they do not close the hole. The
hole is this: `status.currentFrameHash` is only meaningful if it is the hash of a frame
the extension *observed*. If the read runs inline in `processSampleBuffer`, no frames are
observed for the 5.3 s the read takes, so `currentFrameHash` is frozen at the value of the
frame being read — while the heartbeat, on its own 1 Hz timer, keeps ticking. A user who
switches conversation mid-read then gets a record whose `frameHash` matches a
`currentFrameHash` that has not been updated since before the switch. Conditions 1, 4 and
5 all pass and only the admittedly-guessed 20 s backstop stands between the user and a
reply written about somebody else's message. `broadcastPaused()` opens the identical
window from the other direction.

Condition 3 closes it by refusing to treat `currentFrameHash` as evidence until it has
been *re-observed* after `record.readAt`. Condition 2 closes the pause variant. And §3.1
is what makes this cheap rather than a 5.3 s dead zone: because the read is off the
delivery path, fingerprinting continues throughout, so `currentFrameSampledAt` advances
every 250 ms and confirmation normally lands within one sample of the read returning.

Two implementation rules follow and both are testable off-device:

- `status.currentFrameHash` and `status.currentFrameSampledAt` are written **together, in
  one seqlock transaction, on every sampled frame**, and by nothing else. A hash without
  its timestamp is a lie waiting to happen.
- The heartbeat writes `heartbeatAt` and **never touches** `currentFrameHash`,
  `currentFrameSampledAt` or `lastFrameAt`. The heartbeat proves the process is alive.
  `lastFrameAt` proves delivery is alive. They are different failures and conflating them
  is how a wedged handler looks healthy.

### 6.2 The backstop is still a guess

**The 20 s in condition 5 is a guess and I will not pretend otherwise.** The right way to
set it is to instrument the interval between a settle and the Reply tap in real use and put
the cap at p95. Until that data exists, 20 s is chosen to be shorter than the 40 s the
brief calls unacceptable and longer than the 5.3 s a read takes, so a reading is never
declared stale before it has been shown once. It now carries much less weight than it did:
with condition 3 in place it is the fifth line of defence rather than the second.

When Reply is tapped and the current reading fails the gate, the keyboard does **not**
fall back to it. It raises `intent.readNow` and shows the panel's loading state. A 5 s wait
is the honest answer; a stale reply in the user's own name is not.

---

## 7. Which app is the user in

**Partially obtainable, and not in the way the strip currently assumes.**

Verified in `RPBroadcastExtension.h`:

- `- (void)broadcastAnnotatedWithApplicationInfo:(NSDictionary *)applicationInfo`,
  `API_AVAILABLE(ios(11.2)) API_UNAVAILABLE(tvos)`. Its own doc comment: *"Method is
  called when broadcast is started from Control Center and provides extension information
  about the first application opened or used during the broadcast."*
- `RPApplicationInfoBundleIdentifierKey`, `API_AVAILABLE(ios(11.2), macos(11.0))`, is the
  key into that dictionary.

So the header promises a bundle identifier for **one** app — the first one — and only when
the broadcast started from Control Center. It does not promise an update when the user
switches from WhatsApp to Telegram. There is no public API on iOS for the frontmost
application's bundle identifier from any extension, and `NSExtensionContext
loadBroadcastingApplicationInfoWithCompletion:` (present on iOS in the same header)
describes the *broadcasting* app — the one that hosted the picker — which is always us.

This is the section §5.1 leans on. It is not a UI inconvenience; it is the reason no
speculative upload can be made safe on this deployment.

Three moves, in order of confidence:

1. **Store what the header gives, use it where it is true.** Capture the bundle ID into
   `CaptureStatus.firstAppBundleID` when it arrives and show it only in the app's Screen
   Context screen, as history ("started while you were in WhatsApp"). Never as a live
   label, and never as an input to any decision about whether to upload.
2. **Get the app from the reading, which already looks at the pixels.** Add an `app` field
   to `ScreenPrompt.fields`. It must go **last, after `language`** — the repo's field-order
   rule is measured and load-bearing (enumeration first took sender from 21/30 to 29/30;
   splitting `script` from `language` took 22/30 to 29/30), so nothing before it may move.
   Appended last, it is decided with every existing field already written and the current
   order is untouched. Then score it: `Bar/screen-context/` already carries WhatsApp,
   Telegram, Slack, Messages and Mail skins, so this is directly measurable, two runs per
   side per the repo's own rule. Note this arrives *after* the upload, so it can label a
   reading and can never gate one.
3. **Until (2) is scored, do not claim an app at all.** The strip should say what it
   actually knows: *"Reading Maya's message"* when there is a reading, *"Reply can read
   this screen"* when there is not. That is better copy than "Reading WhatsApp" anyway —
   the sender is the thing the user cares about, and the red dot plus the visible strip is
   the capture indicator Apple asks for. `ScreenContext.appName` and `appIcon` become
   optional and the strip stops rendering a guessed SF Symbol.

---

## 8. Teardown and restart

### 8.1 iOS will end the broadcast, and here is the list

Verified in `RPError.h`, `RPRecordingErrorCode`:

| Code | Constant | Cause |
|---|---|---|
| -5806 | `RPRecordingErrorInterrupted` | interrupted by another app |
| -5807 | `RPRecordingErrorContentResize` | multitasking / content resizing |
| -5809 | `RPRecordingErrorSystemDormancy` | **the user pressed the power button** |
| -5811 | `RPRecordingErrorActivePhoneCall` | a call came in |
| -5813 | `RPRecordingErrorCarPlay` | CarPlay became active |

Plus two that produce no error at all: the user stopping from Control Center or the red
status pill (which calls `broadcastFinished()`), and a jetsam kill at the memory limit
(which calls nothing).

### 8.2 The heartbeat is the only signal that covers all of it

`broadcastFinished()` and `broadcastPaused()` are reliable for graceful ends and useless
for a kill. So the extension writes `status.heartbeatAt` at 1 Hz and writes an explicit
`endReason` when it gets a callback. The keyboard's rule: **heartbeat older than 3 s means
ended, reason `.lost`.** A recorded reason wins over the inference. Nothing else is
trusted, because a state machine that believes it is live when the producer is dead is how
a stale reply gets shown.

`broadcastPaused()` is a separate state, not an end. It sets `status.paused = 1` and stops
frame sampling; `broadcastResumed()` clears it. §6 condition 2 is what stops a paused
session from looking fresh, and it needs `lastFrameAt` as well as the flag, because a
delivery stall produces the same symptom with no callback at all.

### 8.3 Restart, which is the weak point of the whole feature

`RPSystemBroadcastPickerView` (verified present and **not** deprecated in
`iPhoneOS26.2.sdk`, `API_AVAILABLE(ios(12.0))`) is the only supported entry point, and it
cannot be triggered programmatically — the user has to tap the system-vended button inside
it. Three paths, in preference order, and the first two are unverified:

1. **Host the picker in the keyboard's `.ended` strip.** A `UIInputViewController` can add
   a `UIView` subview, so the picker will *render*. Whether its button works from a
   keyboard extension is unverified and is risk R8. If it works, this is the whole answer
   and the user never leaves WhatsApp.
2. **Open the app from the keyboard.** `NSExtensionContext openURL:completionHandler:`
   exists in `NSExtensionContext.h` with no availability restriction, but long-standing
   developer reports say it fails from keyboards. Unverified, risk R9. Log the `success`
   flag rather than assuming either way.
3. **Tell the user, in words.** If both fail, the `.ended` strip reads *"Screen context
   stopped. Open AI Keyboard to start it again."* Honest and bad. It is also the reason
   the app's Home screen needs a restart button that is one tap from launch, and the reason
   onboarding should teach the Control Center route: once the user has picked our extension
   in the picker once, iOS's own screen-record button restarts the last destination
   directly. That is the best restart path if it holds, and it is worth verifying early
   because it changes the onboarding script.

Whatever the outcome, `.ended` is a first-class state with a reason, not an absence.
"Screen context stopped because you took a call" is a different message from "…because it
ran out of memory", and the second one is a bug report.

---

## 9. Build sequence

**Phase 0 — settle the numbers that decide the design (device required, currently
blocked).** The probe is landed: `Bar/screen-context/harness/memory.swift` and
`run-memory.sh`. What is left needs an iPhone, and the paired one is offline:

- **R2/R2b, the ceilings.** Allocate in 1 MB steps in each extension and log
  `phys_footprint` until it dies. The last logged value is the answer, once for the
  broadcast extension and once for the keyboard.
- **R3, Vision on an ANE device.** Build `memory.swift` for `arm64-apple-ios` and run it
  as a device unit test over all 30 images. This is the one measurement that could
  reopen an on-device path.
- **R1, the frame.** Log `CVPixelBufferGetPixelFormatType`, width, height and inter-frame
  interval from `processSampleBuffer` for 60 s.
- **R7, the network.** A `URLSession` request from `broadcastStarted`, logged.

None of Phases 3 onward is safe to size without R1, R2 and R7. Phases 1, 2 and 6 do not
depend on them and can proceed.

**Phase 1 — the package split, no behaviour change.**
Create `AIKeyboardShared`, move the Foundation-only types, add `@_exported import`.
`AIKeyboardCoreTests` (including `BackendTransportSuiteTests`) and
`Scripts/prove-app-group.sh` must pass untouched. If they don't, the split is wrong.

**Phase 2 — the channel, provable before anything captures.**
`CaptureChannel`, `SharedPage`, `CaptureStatus` (with all four freshness fields),
`CaptureIntent`, `ScreenReadingRecord`, `FrameFingerprint`. Unit tests for the seqlock and
the fingerprint. Add check 5 to `prove-app-group.sh`: two processes, one mmap'd page, each
sees the other's write. Do not proceed until that check passes on a real keyboard
extension, because everything above it assumes it.

**Phase 3 — the shutter, with no reading in it. This is the budget gate.**
The `AIKeyboardBroadcast` target, `SampleHandler`, `FrameScaler`, `CaptureLoop`,
`MemoryGovernor`. It throttles, fingerprints, heartbeats, and publishes `CaptureStatus` —
and calls no reader at all. Run it for ten minutes against WhatsApp on a device with a
memory graph attached, and **record the baseline**, which §2.4 currently guesses at 20 MB.
Gate: if baseline + one mapped frame + the downscale destination exceeds 30 MB, there is
no room for TLS and the design changes here, before any reading code exists. Set the
`MemoryGovernor` watermark from the measured baseline rather than the placeholder.

**Phase 4 — the on-device question, answered on the right hardware.**
This phase used to re-run `coverage.swift` with `.fast` on macOS. That measured the wrong
quantity (accuracy, not memory) on the wrong deployment (`run-reader.sh` builds with
`xcrun -sdk macosx`, and `.claude/CLAUDE.md` records that macOS and iOS Vision give
different verdicts on these exact images). Replaced with:

> Run `Bar/screen-context/harness/memory.swift` **on a device**, built for
> `arm64-apple-ios`, all 30 images, all configurations, two runs per configuration.
> Confirm the deployment line reads `iOS device` and that the ANE frameworks are mapped.
> Peak under ~30 MB for `.fast` + rectangles reopens the on-device path and sends this
> back to §5.6. Anything above the extension cap closes it for good, and Phase 8 writes
> that down.

Note the accuracy case has to be re-won separately even if the memory case is won:
`.claude/CLAUDE.md` records the routed path scoring below cloud-only on iOS.

**Phase 5 — reading, in the shutter.**
`CloudScreenReader` on the serial read queue inside the broadcast extension, gated by
`MemoryGovernor`, T1 only. Also settle R5 first: re-run the cloud harness at 1206x2622 and
603x1311, two runs each, and confirm the downscale does not cost sender or message
accuracy. If it does, move the downscale up to 804x1748 and take the 2.4 MB — which the
Phase 3 baseline has to have left room for.

**Phase 6 — the consumer.**
`ScreenContextSession` rewritten as a channel consumer. The §6 freshness gate, with tests
for **all five** conditions, including the mid-read conversation switch and the
`broadcastPaused()` window that condition 3 exists to catch. `.ended` and `.paused` in
`ScreenContextState` and in the strip. The strip stops naming apps and gains the pre-tap
offer state.

**Phase 7 — the budget and restart.**
Daily and session read budgets in `SharedStore` and their UI. The `isSecureTextEntry`
guard and R14. R8 and R9 on device, then whichever restart path survives. No speculative
reads, now or later, without the signal §5.1 names.

**Phase 8 — the docs that are now wrong.**
`README.md` lines 128-132 are replaced per §5.3 and lines 110-127 keep. The mock-to-real table's
`MockScreenContext` row. The five stale privacy comments in §5.2. `.claude/docs/architecture.md`'s
directory map and data flow. And a `.claude/CLAUDE.md` gotcha, because this is the fact
someone will otherwise rediscover the hard way:

> **Vision's text recogniser cannot live in an iOS extension, and the simulator will tell
> you it can.** Over the 30 bar screens in one process, peak `phys_footprint` is 199.8 MB
> at `.accurate` and 84.7 MB at `.fast` on macOS 26.5.1; even
> `VNDetectTextRectanglesRequest` alone is 67.9 MB. On the iOS Simulator the same code is
> 174.8 / 18.1 / 10.3 MB. The difference is the Apple Neural Engine frameworks, which
> macOS maps and the simulator does not — and a phone is an ANE configuration, so the
> simulator is the optimistic deployment, not the pessimistic one. Extensions are capped
> around 48-50 MB. Resolution does not help: 1/16 of the pixels moves `.accurate` by
> 10-14%.
> `Bar/screen-context/harness/run-memory.sh` re-takes all of it and asserts the ANE
> control both ways.

---

## 10. Open risks

Ordered by how much of the design they can invalidate.

| # | Risk | What would resolve it |
|---|---|---|
| **R0** | **App Review.** A ReplayKit broadcast upload extension used to OCR the user's screen for a keyboard is not what the API is for. Rejection under 2.5.1 (private/undocumented use of an API) or 5.1.2 (data use) is a live possibility, and no amount of engineering answers it. This is the risk most likely to kill the feature and it is not technical. Deleting the speculative upload (§5.1) helps the 5.1.2 half and does nothing for the 2.5.1 half. | A pre-review question to App Review describing the flow, or a TestFlight external build. Ask before Phase 3, not after Phase 8. |
| **R2** | Is the broadcast ceiling really ~50 MB on iOS 26? It is in no header on this machine. §2.4 has 6-11 MB of headroom against it, so a 40 MB reality kills the design. | Device build that allocates in 1 MB steps and logs `phys_footprint` until it dies. The last logged value is the answer. |
| **R2b** | Is the keyboard ceiling really ~48 MB? Reported by review, not re-derived here, and it is one of the two numbers §1 rests on. | Same experiment, in the keyboard extension. |
| **R1** | Pixel format, resolution and rate ReplayKit actually delivers. 7.6 MiB of the budget swings on 420f versus BGRA. | Log `CVPixelBufferGetPixelFormatType`, width, height and inter-frame interval from `processSampleBuffer` on device for 60 s. |
| **R2c** | The broadcast extension's own baseline, guessed at 20 MB, is the largest unmeasured line in §2.4. | Phase 3: the shutter with no reading in it, on a device, memory graph attached. |
| R3 | Vision on an ANE **device**. Every measurement in this document is simulator (no ANE) or macOS (ANE). The device is the third point and it is missing. | `memory.swift` built for `arm64-apple-ios`, run as a device unit test, all 30 images, two runs. Under ~30 MB for `.fast` reopens §5.6; near the macOS figure confirms this design. |
| R7 | `URLSession` + TLS footprint inside a broadcast upload extension, guessed at 4-8 MB. Network *working* is almost certain — uploading is the extension point's purpose — but the memory it costs is not. | Request from `broadcastStarted` on device, with `MemoryGovernor` sampled before and during. |
| R5 | Does 603x1311 hurt the cloud reader? Bar scores were taken at 1206x2622. | Cloud harness at both sizes, two runs each side, compare sender / message / language. |
| R6 | Does `broadcastAnnotatedWithApplicationInfo` fire on every app switch or only the first? The header says the first. If it fired on every switch, §5.1 would have to be re-argued — that is how load-bearing it is. | Device log across three app switches inside one broadcast. |
| R8 | Can a keyboard extension host a working `RPSystemBroadcastPickerView`? Decides whether restart is in-place or requires leaving the app. | Device build; tap it. |
| R9 | Can a keyboard extension call `extensionContext.open(_:)`? Header allows it, folklore says no. | Device build; log the `success` flag. |
| R10 | Does two processes mmap'ing one file in an App Group container actually give coherent shared memory on iOS? Standard POSIX says yes; iOS sandboxing has surprised people before. | Check 5 in `prove-app-group.sh`. Cheap, and Phase 2 blocks on it. |
| R11 | Does the broadcast survive a screen lock? `RPRecordingErrorSystemDormancy` suggests the power button ends it. If a lock ends every session, the feature's session length is measured in minutes and onboarding has to say so. | Lock the device mid-broadcast; observe whether `broadcastFinished()` fires. |
| R12 | The 20 s staleness backstop is a guess. Less load-bearing now that §6 condition 3 exists, but still a guess. | Instrument settle-to-tap interval; set the cap at p95. |
| R13 | Does protected content actually black out under ReplayKit? The README already claims it. §5.1 deliberately does not rely on it. | Capture a banking app and a DRM video on device. |
| R14 | Does `textDocumentProxy.isSecureTextEntry` actually reflect the host field? The protocol chain is verified in the headers; whether hosts populate it is not. | Keyboard in a password field on device; log the trait. Ship the guard either way. |

---

## How the numbers were taken

**§2.3 and §2.4's one measured line.** `Bar/screen-context/harness/memory.swift`, driven by
`Bar/screen-context/harness/run-memory.sh`, both in this repo. The probe reads
`phys_footprint` out of `task_info(mach_task_self_, TASK_VM_INFO, ...)` after each of the
30 images in `Bar/screen-context/images/`, one image alive at a time, one reused request
per process. It reports its own deployment and the Neural Engine frameworks mapped into
it, and it exits non-zero rather than printing a number it could not take.

```
Bar/screen-context/harness/run-memory.sh                       # both deployments
SCALES="1.0 0.5 0.25" Bar/screen-context/harness/run-memory.sh  # the resolution sweep
```

Taken 2026-08-08 on macOS 26.5.1 (25F80) and on the iOS 26.2 arm64 simulator runtime
(iPhone 17 Pro), Xcode 26.2 (17C52). **Neither is a device.** The script asserts that
macOS maps `AppleNeuralEngine.framework` and the simulator does not, and fails if that
ever stops being true, because that asymmetry is the reason the two columns differ and the
reason the simulator column must not be read as a phone.

An earlier version of this document reported single-image deltas from a probe at
`Bar/screen-context/harness/memory.swift` that did not exist in the repo, so its
"reproducible" preamble was false. It is true now.

**The JPEG size table (§2.2).** Pillow 11.3.0 on macOS over all 30 images at quality 70,
LANCZOS resample. CoreGraphics will not produce byte-identical results; the ratios are what
the design depends on.

**Everything else in §2.2 and §2.4** is arithmetic or an estimate, and each row says which.
