# Screen capture: where the reading happens

Design for turning `ScreenContextSession.submit(_:appName:appIcon:)` from a seam into
a live pipeline. Written 2026-08-08 against Xcode 26.2 (17C52), iPhoneOS26.2.sdk,
macOS 26.5.1 (25F80).

Revised twice the same day. The first revision fixed an inverted memory argument and a
missing privacy argument. **This one retracts the explanation that revision put in its
place.** §1 and §2.3 claimed the macOS/Simulator gap was the Apple Neural Engine and that
a phone, being an ANE configuration, would look like macOS. One line falsifies it:

```swift
try request.supportedComputeStageDevices
```

| Request | macOS 26.5.1 | iOS Simulator 26.2 |
|---|---|---|
| `VNDetectTextRectanglesRequest` | `[cpu]` | `[cpu]` |
| `VNRecognizeTextRequest(.fast)` | `[cpu]` | `[cpu]` |
| `VNRecognizeTextRequest(.accurate)` | `[ane, cpu, gpu]` | `[cpu, gpu]` |

The Neural Engine is not in the picture for the shape detector or for `.fast`, which are
the only two configurations an on-device path would use. It appears in exactly one row,
and that row is the configuration this design rejects for other reasons. Every claim built
on "a phone is an ANE configuration, so the Simulator is the optimistic deployment" is
withdrawn, and the on-device path that claim was used to close is **reopened as undecided**.
§2.3 now says what was actually measured instead, which is a difference in memory
*accounting*, not in computation, with no way to tell from here which side a phone falls on.

Three rules this document holds itself to, because the first version broke all three and
the second version broke the third:

1. **Every number says which deployment produced it.** `iOS Simulator`, `macOS`, or
   `iOS device`.
2. **No device number appears anywhere, because none exists.** The paired iPhone is
   offline. Everything that needs a device is labelled **unproven** and named as such.
3. **Every API claim is quoted from a header on this machine, with the path**, or
   marked **unverified** with the experiment that would settle it. A claim about *why* a
   number is what it is is an API claim and needs the same standard. That is the rule the
   second version broke: it explained a measurement with a mechanism it never measured.

The probes behind §2 and §6 are `Bar/screen-context/harness/memory.swift` (driven by
`run-memory.sh`) and `Bar/screen-context/harness/frame-hash.mjs`. Both exist in the repo
and both fail rather than skip when they cannot measure, in the manner of
`Scripts/prove-app-group.sh`.

---

## 0. Evidence status, up front

| Section | Status |
|---|---|
| §1 recommendation | **Decided, and it does not rest on §2.** It rests on an on-iOS end-to-end accuracy measurement (`AIKeyboardCoreTests/ScreenContextBarTests.swift`). §2 is a second, weaker argument that is currently unresolved. |
| §2 memory | **UNRESOLVED.** Measured on two deployments that disagree by 6x, with the disagreement traced to memory accounting and not to computation. Neither is an iPhone. |
| §1.3 on-device path | **UNDECIDED.** The threshold this document set for itself is cleared on the only deployment that runs iOS Vision code and missed by 2x on the one that does not. A device settles it; nothing here does. |
| §3 data flow, §4 files | Design. Sized by §2, so provisional with it. |
| §5 privacy | Decided. Does not depend on §2 except to *raise* the stakes. |
| §5.5, §6 freshness | **Measured**, `Bar/screen-context/harness/frame-hash.mjs`, and the measurement changed the design: the previous crop band and the 64-bit hash both failed it. |
| §7 which app is on screen | **Verified** against `RPBroadcastExtension.h`. |
| §8 teardown | **Verified** against `RPError.h` and `RPBroadcast.h`. |

---

## 1. Recommendation

**Option (c): the broadcast extension is a shutter with a phone line. It reads nothing
itself.** It throttles 60 fps down to a 4 Hz fingerprint, keeps exactly one reusable
downscaled buffer, and — only when the user taps Reply — encodes one JPEG and hands it
to `CloudScreenReader` over `BackendTransport`. Only text crosses the App Group:
a `ScreenReadingRecord` (sender, message, language) and a fixed-layout `CaptureStatus`
page (heartbeat, frame identity, counters).

**Screen reading in the shipping capture flow is cloud-only. That is the safe default, and
the argument for it is accuracy, measured on the deployment that matters.**

### 1.1 The measurement that carries the recommendation

`AIKeyboardCoreTests/ScreenContextBarTests.swift` runs the whole path — one
`ScreenContextSession`, all 30 corpus frames, `RoutedScreenReader` deciding per frame,
only the network replaced — **on iOS**, and scores it against the same ground truth the
cloud harness is scored against:

| | routed through Vision | cloud for every frame |
|---|---|---|
| sender | 27/30 | **30/30** |
| keyboard language | 29/30 | **30/30** |
| message, exact | 16/30 | **18/30** |
| message, within 90% | 24/30 | **25/30** |

Both columns are scored against the same `cloud_outputs.json`, re-recorded 2026-08-08 at
602x1310 JPEG q70 — the size and encoding the product actually sends, rather than the
full-size PNG every earlier reading in this document used. The comparison is what this
table is for and it is apples to apples: the on-device path costs about three points of
sender. The absolute figures are a reading with a date on it, because the model is served
behind a moving alias with no dated version to pin to; a repeat run minutes later scored
29/30 sender and is committed as `cloud_outputs_repeat.json` so the spread stays measured.

Routing costs three points of sender and three of exact message. And the eight frames the
on-device gate accepts (`byEngine["vision"]?.n == 8`) include **three it answers wrongly**:
`wa-07`, whose only correct answer is silence, comes back as a message the user already
replied to with the bubble timestamp glued on; `sl-05` comes back as keyboard key caps;
`ml-01` returns the user's own quoted history. The same sources on macOS accept 9 and
answer 5, all 5 right — which is why a macOS reading of this must never be quoted as the
product's, and why this table is the one that counts.

**That measurement is on iOS, end to end, and it carries the recommendation on its own.**
The on-device path is not free accuracy that happens to be private. On this bar it is
worse accuracy, and three of its eight answers are wrong in the user's name. Even if
memory turned out to be free, this would have to be re-won before an on-device path
shipped.

### 1.2 The memory argument, which is a second argument and is currently unresolved

Every process that could read the screen while the user is in another app is memory-capped:
the broadcast upload extension at ~50 MB and the keyboard extension at ~48 MB. The
containing app has no cap and is not running when the user is in WhatsApp, so it is not a
candidate in this flow. (Neither cap is in any header on this machine; §2.1 says what each
rests on.)

Against those caps, §2.3 measures the same Vision code costing **6x more on macOS than on
the iOS Simulator**, and the reason is not computation:

- The detector and `.fast` are `[cpu]` on both deployments, and neither deployment is
  running a bigger model than the other: `Vision.framework` ships the same Espresso model
  assets under the same names and sizes on macOS 26.5.1 and in the iOS 26.2 simulator
  runtime (spot-checked on `mrcdetector.espresso.weights_nonane`, 3,967,936 bytes on both,
  a name whose `_nonane` suffix agrees with the compute-device table).
- What differs is where the kernel charges the bytes. Running the detector over 30 frames
  moves `phys_footprint` by **+63.2 MB on macOS** (of which `TASK_VM_INFO` itemises
  32.7 MB as `ledger_tag_graphics_footprint` and ~14 MB as anonymous `internal`; the rest
  is unitemised, and `vmmap -summary` does not attribute it to any region either) and by
  **+4.5 MB on the iOS Simulator**, where the growth instead lands in `external` — clean,
  file-backed resident memory, +10.7 MB, which the footprint ledger does not charge.
- Neural ledgers are 0.0 on both deployments for the detector and `.fast`. Even for
  `.accurate` on macOS, where the ANE is genuinely used, the kernel puts 113-171 MB on
  `ledger_tag_neural_nofootprint` and **0.0 on `ledger_tag_neural_footprint`** — that is,
  the ANE's memory is explicitly not charged to the number jetsam reads.

**We do not know which of those two accounting behaviours a device does**, and nothing on
this machine can find out. So the memory argument does not currently point anywhere. It is
not evidence for cloud-only and it is not evidence against it.

### 1.3 The on-device path is undecided, not closed

This document set its own reversal threshold in its previous revision: peak footprint
under **~30 MB** for `.fast` + rectangles over all 30 images in one process. Measured:

| Configuration | iOS Simulator 26.2 | macOS 26.5.1 |
|---|---|---|
| `VNDetectTextRectanglesRequest` alone | 9.9 / 10.3 / 11.3 | 66.7 / 67.0 / 72.6 |
| `.fast` + rectangles | 18.1 / 20.7 / 22.9 | 84.6 / 88.2 / 93.4 |

The iOS Simulator is the only deployment on this machine that runs the iOS build of
Vision, and it clears the threshold on every run. macOS misses it by 2-3x. **"Unknown
pending a device measurement" is the honest state**, and it is the state this section is
in. `VisionScreenReader` is not deleted, is not deprecated, and stays as the bar-scored
reference and as the in-app playground path.

What is *not* undecided: §1.1. If the device measurement comes back cheap, the memory
objection falls and the accuracy objection is untouched.

**Resolution is not a knob**, on either deployment. At 301x655 — 1/16 of the original
pixel count — `.accurate` still peaks at 171.7 MB (macOS) / 157.3 MB (iOS Simulator) and
`.fast` at 71.5 MB (macOS) / 19.9 MB (iOS Simulator). The cost is not activations and no
downscale reaches it.

### 1.4 What settles it

Run `Bar/screen-context/harness/memory.swift` as a device unit test. It compiles for
`arm64-apple-ios` unchanged, reports `deployment = iOS device`, and now also reports
`supportedComputeStageDevices` and the ledger breakdown, so a device run says not just how
much but *where charged* — which is the quantity actually in dispute. Under ~30 MB for
`.fast` + rectangles and the memory objection is gone; near the macOS figure and it stands.
Nothing short of that moves it, and in particular no further simulator or macOS run does.

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
| Keyboard extension | **~48 MB** | Reported by the independent review that produced the first revision, 2026-08-08. Not re-derived here and not in any header. Unverified on device here (R2b). |
| Containing app | none | But it is not running when the user is in WhatsApp, so it cannot be the reader in the capture flow. It *is* the reader in the in-app playground. |

The two caps are close enough that they do not change any decision below. What does change
decisions is which side of §2.3's 6x accounting gap a phone lands on, and that is unknown.

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

`FrameScaler.target` rounds down to even, so the shipped destination is **602x1310**, not
the 603x1311 this section rounds to. Re-measured at that exact size the JPEG figures are
unchanged to the kilobyte: 66 / 98 / 103.

Fingerprint reduction: 32x64 greyscale = 2,048 bytes. Negligible, and §5.5 is where the
band it is taken over is decided.

#### 2.2.1 The downscale costs no accuracy — R5, closed

The bytes above were never the question; the question was whether the model can still read
602x1310. Measured 2026-08-08 with `Bar/screen-context/harness/vertex_vision.py`, which now
takes `VERTEX_IMAGE_SCALE` and `VERTEX_IMAGE_FORMAT`. Nothing else moved: same prompt, same
schema, same `propertyOrdering`, same `thinkingBudget: 512`, same model, all four cells in
one sitting, two runs each minimum:

| Sent | runs | bytes med / p90 | latency med / p90 | exact | +near | sender | language | traps |
|---|---|---|---|---|---|---|---|---|
| 1206x2622 PNG — what the bar always sent | 3 | 250 / 341 KB | 5.9 / 6.5 s | 18/30 | 6 | 26/30 | 28/30 | 0 |
| 602x1310 PNG | 2 | 207 / 288 KB | 5.3 / 6.5 s | 17/30 | 5 | 28/30 | 29/30 | **1** |
| 1206x2622 JPEG q0.70 | 3 | 176 / 254 KB | 5.2 / 5.9 s | 18-19/30 | 6 | 28/30 | 28/30 | 0 |
| **602x1310 JPEG q0.70 — what `FrameScaler` sends** | 3 | **66 / 98 KB** | **5.0 / 6.0 s** | 18-19/30 | 7 | **29-30/30** | **30/30** | 0 |

No axis moves by more than one between the two sizes at either encoding, and at the
encoding that ships the half-size frame is ahead on sender and keyboard language. **So
`FrameScaler.scale` stays at 2**, and the 804x1748 contingency is dead.

Three things this run turned up that are worth more than the decision itself:

1. **The encoder was the second unmeasured variable and nobody had noticed.** The bar sends
   PNG; every path in the product sends JPEG q0.70. Half-size JPEG is 74% smaller than the
   PNG the bar scored and scores at or above it on every axis, so this is a saving with no
   accompanying cost — but it had never been measured, and "the same encoder, at the same
   quality, the bar scored the reader at" in `FrameScaler.encode` was not true.
2. **Totals hide per-frame churn.** Eleven of thirty frames change verdict between the two
   PNG sizes (4 better, 6 worse, 1 wrong both ways) and five between the two JPEG sizes
   (4 better, 1 worse). Read the per-entry diff in `Bar/screen-context/README.md`, not the
   total. The single trap returned anywhere in the 2x2 is `im-03` at 602x1310 PNG, which is
   not a configuration anything ships.
3. **The model reproduces itself and does not reproduce the committed file.** Repeat runs
   of a cell returned byte-identical answers on all 30 frames across 45 minutes, with two
   single-frame exceptions — and re-encoding the corpus to a different PNG byte stream with
   identical pixels reproduced the first run exactly, which rules out a response cache. The
   drift is between days, not between calls: two runs of one configuration minutes apart
   disagree on **2 of 30** and move sender by one, while runs a day apart moved roughly a
   third of the corpus with nothing in the repo changed. And there is no dated model version
   to pin to — every dated handle 404s, and the API echoes the alias back as its own
   `modelVersion`. So any comparison on this bar has to have both sides run in one sitting,
   and any number quoted from a committed `*_outputs.json` is a reading with a date on it.

Latency moved 5.9s -> 5.0s median, which is real but not the point: this ran over a laptop
uplink where 184 KB of saved payload is under 200 ms. The bytes are the figure that
converts to seconds on a phone's cellular link.

### 2.3 Vision, measured on two deployments, neither of them a phone

`Bar/screen-context/harness/run-memory.sh`. Physical footprint via
`task_info(mach_task_self_, TASK_VM_INFO)` — the same number jetsam reads — sampled after
every image, across **all 30 bar screens in one long-lived process**, one image alive at a
time. One reused request object per process, which is the shape a long-lived extension
would have.

**Peak** is the number that decides the design, because an extension dies at its ceiling
rather than degrading. Base footprint is 2.3-4.0 MB (macOS) and 5.5-11.0 MB (iOS
Simulator); the tables are absolute peaks, so subtract the base for a delta.

| Configuration, 1206x2622 | iOS Simulator 26.2, arm64 — peak MB | macOS 26.5.1 — peak MB |
|---|---|---|
| decode only (the floor) | 8.9 / 10.3 | 4.5 / 5.8 |
| decode + JPEG encode q0.70 | 10.5 | 4.2 |
| `VNDetectTextRectanglesRequest` alone | 9.9 / 10.3 / 11.0 / 11.1 / 11.3 | 66.7 / 67.0 / 69.2 / 72.5 / 72.6 |
| `.fast` + rectangles | 18.1 / 20.7 / 22.8 / 22.9 | 84.6 / 84.7 / 88.2 / 91.1 / 93.4 / 95.1 |
| `.accurate` + rectangles | 174.8 / 174.8 / 176.5 | 194.1 / 198.0 / 198.2 / 206.9 |
| `.accurate` as a *stock* request (no auto-detect, no correction, `en-US`) | 100.4 | 111.8 |

Resolution sweep, same probe, same 30 images:

| Configuration | scale 1.0 (1206x2622) | scale 0.5 (603x1311) | scale 0.25 (301x655) |
|---|---|---|---|
| `.fast`, iOS Simulator | 18.1 | 19.7 | 19.9 |
| `.fast`, macOS | 84.7 | 73.3 | 71.5 |
| `.accurate`, iOS Simulator | 174.8 | 177.8 | 157.3 |
| `.accurate`, macOS | 199.8 | 184.5 | 171.7 |

#### 2.3.1 The 6x gap is accounting, not computation

The probe now asks `supportedComputeStageDevices` before it runs anything, and prints the
ledger tags `TASK_VM_INFO` breaks the footprint into. Measured 2026-08-08:

| | macOS 26.5.1 | iOS Simulator 26.2 |
|---|---|---|
| `VNDetectTextRectanglesRequest` | `main=[cpu]` | `main=[cpu]` |
| `VNRecognizeTextRequest(.fast)` | `main=[cpu]` | `main=[cpu]` |
| `VNRecognizeTextRequest(.accurate)` | `main=[ane, cpu, gpu]` | `main=[cpu, gpu]` |

Three consequences, and the first two retract earlier text:

1. **The Neural Engine is irrelevant to the two configurations that matter.** The detector
   and `.fast` are cpu-only on both deployments. Pinning them to the CPU explicitly with
   `setComputeDevice(_:for:)` changes nothing, as it should not: macOS `rects` peaks at
   73.3 MB pinned against 72.5 MB unpinned, and `.fast` at 88.2 MB pinned against 93.4 MB
   unpinned, both inside run-to-run spread.
2. **It is not a bigger model on one side.** `Vision.framework` ships the same Espresso
   model assets under the same names and sizes on macOS 26.5.1 and in the iOS 26.2
   simulator runtime; spot-checked on `mrcdetector.espresso.weights_nonane`, 3,967,936
   bytes on both. That file's `_nonane` suffix and the compute-device table agree with each
   other. (Which asset the text detector loads is *not* verified here; the claim is only
   that the two deployments are not shipping different weights.)
3. **The two deployments charge the same work to different ledgers.** Detector alone, over
   30 frames, in MB:

   | | macOS base -> end | iOS Simulator base -> end |
   |---|---|---|
   | `phys_footprint` (what jetsam reads) | 3.9 -> **67.0** | 5.8 -> **10.3** |
   | `resident_size` | 13.4 -> 31.3 | 37.7 -> 53.1 |
   | `internal` (anonymous, dirty) | 3.4 -> 17.4 | 4.2 -> 8.6 |
   | `external` (file-backed, clean) | 10.0 -> 13.8 | 33.4 -> **44.1** |
   | `ledger_tag_graphics_footprint` | 0.0 -> **32.7** | 0.0 -> 0.0 |
   | `ledger_tag_neural_footprint` | 0.0 -> 0.0 | 0.0 -> 0.0 |

   macOS adds 63.2 MB of footprint for a cpu-only request. About 32.7 MB of it is itemised
   as *graphics*, about 14 MB as anonymous `internal`, and the remainder is unitemised:
   `vmmap -summary` on the same process reports its dirty total equal to the footprint
   while the itemised region rows sum to roughly a third of it, and its
   `IOAccelerator (graphics)` region is 720 KB — three orders of magnitude below the
   graphics ledger. A decode-only control leaves the graphics ledger at 0.0 on macOS, so
   the allocation is created by the first Vision request and by nothing else.

   The iOS Simulator adds 4.5 MB of footprint for the same request and grows `external` by
   10.7 MB, which is file-backed clean memory: charged to resident, not to footprint, and
   evictable without swap. On macOS the same process has **no** `.espresso.weights` file
   mapped or open at that point — `vmmap` lists no such region and `lsof` no such
   descriptor — so whatever the weights cost there is anonymous and dirty. Same work, two
   ways of getting it into memory, and only one of them is charged to the ledger jetsam
   reads.

   **A device runs the iOS build.** That does not prove it does what the Simulator does —
   the Simulator is an x86-lineage sandbox running on this Mac's kernel, and its VM
   behaviour is not a phone's. But it does mean the Simulator is no longer, on this
   evidence, obviously the optimistic side. It may be the representative one. Neither
   direction is established and this document takes neither.

   Even for `.accurate` on macOS, where the ANE is really used, the kernel puts 113.1 MB
   (after one call) rising to 170.7 MB on `ledger_tag_neural_nofootprint` and **0.0 on
   `ledger_tag_neural_footprint`**. Where the Neural Engine appears at all, its memory is
   explicitly outside the ledger jetsam kills on.

#### 2.3.2 `.accurate` has no peak, it has a slope

The 199.8 MB this document used to quote as `.accurate`'s peak is not a ceiling. It is a
reading of one point on a curve, and the curve is a function of how many *distinct* images
the process has seen:

| macOS 26.5.1, `.accurate` | sampled peak | final | kernel `ledger_phys_footprint_peak` |
|---|---|---|---|
| 30 calls, 30 distinct images | 198.0 | 177.1 | 225.2 |
| 60 calls, 30 distinct images (two passes) | 206.6 | 194.1 | 232.5 |
| 30 calls, 1 distinct image | 124.2 | 124.2 | 150.4 |

| iOS Simulator 26.2, `.accurate` | sampled peak | final | kernel peak |
|---|---|---|---|
| 30 calls, 30 distinct images | 174.8 | 155.0 | 204.6 |
| 60 calls, 30 distinct images | 179.5 | 158.6 | 219.3 |
| 30 calls, 1 distinct image | 95.7 | 95.7 | 118.5 |

Repeating one image costs 60-80 MB less than thirty different ones, and a second pass over
the same thirty still climbs rather than plateauing. So the cost accumulates with the
variety of content seen, not with the number of calls, and the corpus is thirty screens —
a phone in a day sees thousands. **There is no measured ceiling for `.accurate` in a
long-lived process, and this document does not have one to quote.** Any figure for it is a
lower bound tagged with the call count and the distinct-image count that produced it.
`PASSES=` and `SAME_IMAGE=` on `memory.swift` re-take the table.

The two cheap configurations do not do this. Over 60 calls the iOS Simulator plateaus:
rects 11.0 MB (against 9.9-11.3 at 30 calls) and `.fast` 22.8 MB (against 18.1-22.9). If
an on-device path is ever revisited, that difference is a reason to keep it away from
`.accurate` independently of everything else.

#### 2.3.3 The two probes never disagreed

The previous revision recorded that "the independent review's probe did not reproduce this
climb (it saw 84 -> 104 over the same 30 screens)" and filed it as two probes disagreeing
about the shape of a curve. They were measuring two different requests.

The earlier probe used a stock `VNRecognizeTextRequest` — `.accurate` by default, with
`automaticallyDetectsLanguage` never set and `usesLanguageCorrection` left alone. That is
this document's `accurate-en` row: **100.4 MB (iOS Simulator) / 111.8 MB (macOS)**, which
brackets its 104/114 exactly.

The configuration this product ships is `VisionScreenReader.swift:101-105`:

```swift
recognizeText.recognitionLevel = .accurate
recognizeText.usesLanguageCorrection = true
recognizeText.automaticallyDetectsLanguage = true
```

which is the `accurate` row, 174.8 / 198.0. **The `accurate` row is the one to quote as the
product's cost.** Automatic language detection is not a free flag: it is most of the
difference between 100 MB and 175 MB, and it is also, per §2.3.2, the plausible mechanism
for the climb — each newly detected language brings its own state into a process that never
lets go of it.

#### 2.3.4 What the routing gate costs on its own

`VisionScreenReader`'s whole routing decision depends on `VNDetectTextRectanglesRequest`
running alongside recognition. On the iOS Simulator that request is 9.9-11.3 MB peak and
plateaus. On macOS it is 66.7-72.6 MB peak — over both extension caps before any
recognition runs. Which of those a phone does is the same open question as everything else
in this section, and it is R3.

### 2.4 The extension's budget, assembled — and what is still unmeasured

> **This total is conditional.** Two of six lines are unmeasured estimates, and they are
> the two largest after the frame itself. Phase 3 exists to measure them, and the design
> does not proceed past Phase 3 without them.

Recommended configuration: 602x1310 downscale, cloud read, no Vision anywhere. §2.2.1
measures the downscale and it costs nothing.

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
proven to fit. **Phase 3 is the gate**: build the shutter with no reading in it, run it on
a device against WhatsApp for ten minutes with a memory graph attached, and read the real
baseline. If baseline + frame + downscale exceeds 30 MB, there is no room for TLS and the
design changes before any reading code is written.

Two consequences that must be in the code, not in a comment:

- **Never link `AIKeyboardCore` into the broadcast extension.** `Models.swift`,
  `Theme.swift`, `KeyboardController.swift`, `Feedback.swift` and every panel import
  SwiftUI or UIKit, and `SharedStore` reaches `Feedback`, so linking the package drags
  UIKit and SwiftUI into a ~50 MB process for nothing. §4 splits out `AIKeyboardShared`.
- **The extension polices its own footprint.** `MemoryGovernor.footprintMB()` wraps the
  same `task_info(TASK_VM_INFO)` call `memory.swift` uses. Refuse to start a read above a
  watermark and publish `CaptureStatus.degraded` instead. A visible degraded state beats a
  jetsam kill, because a jetsam kill ends the broadcast and only the user can restart it.

  **Built, and the placeholder watermark is not what shipped.** This paragraph used to say
  35 MB and then say the watermark could not be set until Phase 3 measured a baseline — a
  combination that refuses every read of every session if the baseline is above it, which
  is the feature switched off by a guess with nothing in the UI to act on. What ships
  instead is `max(ceiling - reserve, baseline + reserve)` with `ceiling` 50 MB and
  `reserve` 10 MB, where the baseline is measured in this process at `broadcastStarted`:
  40 MB on a normal session, and a session that starts above 40 MB raises its own
  watermark and logs the baseline rather than refusing everything. A guess does not
  overrule a measurement. Phase 3 replaces the two guesses; it is not needed to make the
  rule safe.

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
  |    -> lock base addr, reduce to 32x64 grey       |  2 KB, conversation band only
  |    -> FrameFingerprint: identity + changeScore   |
  |    -> publish identity + sampledAt to status.bin |  every sampled frame, always
  |    -> ScreenReadService.claim(...) ?             |
  |         no  -> return                            |
  |         yes -> scale to 602x1310 (reused buf)    |  3.0 MB, overwritten in place
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
        +-- channel/status.bin    fixed 256 B, mmap MAP_SHARED, 1 Hz + every sample
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
  |  Reply tapped -> secure-field guard, §3.3        |
  |               -> intent.readNow = seq+1          |
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

Both pages are timestamps, counters and fixed-width hashes. Both stay at the container
default `.completeUntilFirstUserAuthentication` on purpose: an mmap'd file marked
`.complete` becomes unreadable when the device locks, and touching it then is a SIGBUS, not
an error return.

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

Subject to three refusals, all of which publish a counter rather than failing silently:

- Full Access is off, so the keyboard cannot reach the container at all (§3.5).
- `MemoryGovernor` is above the watermark (`refusedMemory`, and `degraded` while it lasts).
- A read is already in flight (`refusedInFlight`).

A fourth was listed here — a session or daily read budget, counted in `refusedBudget` and
ending the session with `ScreenContextEndReason.overBudget`. No budget was ever built, so
nothing could move either, and both have been deleted rather than left as a zero the
status screen invites the user to trust. They come back with the budget.

**There is no speculative trigger.** The previous version had one — T2, default on, firing
whenever the keyboard was visible and the screen had settled. It is deleted. §5.1 is the
argument, and it is not a close call.

#### 3.3.1 The secure-field guard fails closed, and the naive spelling of it fails open

One more refusal, a privacy rule rather than a resource rule: **never fire a read while the
focused field is a secure text entry field.**

The protocol chain is real. `UITextDocumentProxy` conforms to `UIKeyInput`
(`UIInputViewController.h:19`), which conforms to `UITextInputTraits`
(`UITextInput.h:24`), which declares `isSecureTextEntry` (`UITextInputTraits.h:257`).

**But that declaration is inside an `@optional` block.** `UITextInputTraits.h:237` opens
the protocol, `:239` is `@optional`, and every property from there down — including
`secureTextEntry` at `:257`, `textContentType` at `:260` and `keyboardType` at `:253` — is
optional. Verified by compiling against `iPhoneSimulator26.2.sdk`:

```
error: cannot convert value of type 'Bool?' to specified type 'Never'      // isSecureTextEntry
error: cannot convert value of type 'UITextContentType??' ...              // textContentType
error: cannot convert value of type 'UIKeyboardType?' ...                  // keyboardType
```

So in Swift `proxy.isSecureTextEntry` is `Bool?`, and the obvious guard

```swift
if proxy.isSecureTextEntry == true { refuse() }   // WRONG: nil permits
```

**permits the read on every host that does not implement the trait.** A guard whose default
on an unknown host is "allow" is not a guard; it is a comment. The design requires the
opposite default:

```swift
/// Fails closed. `nil` is a host that did not answer, and an unanswered question
/// about whether this is a password field is answered "yes" here.
enum SecureField {
    static func permitsRead(secure: Bool?, contentType: UITextContentType??) -> Bool {
        guard secure == false else { return false }          // true or nil -> refuse
        guard let inner = contentType, let type = inner else { return true }
        return !sensitive.contains(type)
    }

    static let sensitive: Set<UITextContentType> = [
        .password, .newPassword, .oneTimeCode, .creditCardNumber, .creditCardSecurityCode,
    ]
}
```

Three rules that follow, and they are the design, not an implementation detail:

1. **`nil` refuses.** Only a positive `false` permits.
2. **`textContentType` is a second, independent refusal, never a permission.** It is
   `UITextContentType??`; the outer `nil` means the host did not implement the property and
   the inner `nil` means it implemented it and set nothing. Neither is evidence of safety,
   so both fall through to whatever `isSecureTextEntry` said, and a value in the sensitive
   set refuses on its own. The five constants are verified in `UITextInputTraits.h:305-309`
   and `:324`.
3. **A refusal for this reason is counted and named**, as `refusedSecure` and
   `refusedSecureUnknown` separately. This is what turns R14 from folklore into a number: if
   the field is genuinely never populated through the proxy, the second counter will be
   equal to the tap count on the first device run and the guard as written will have
   disabled the feature. That is a thing to discover from a counter in Phase 7, not from a
   silent hole in shipping code — and the resolution is then to find a different signal, not
   to flip the default.

   **Corrected when it was built: the two counters are in `CaptureIntent`, not
   `CaptureStatus`.** This section put them on the status page, and that page cannot hold
   them. The guard runs in the keyboard, because the keyboard is the only process that can
   see the focused field's traits at all; `status.bin` has exactly one writing *process* and
   the keyboard is not it. `SharedPage`'s lock serialises threads, not processes, so a second
   process writing that page would tear it with nothing to catch the tear. `intent.bin` is
   the page the keyboard owns and the producer already reads, so the counters go there.
   The tap arithmetic still works and is the thing to read on a device: on a first run,
   where no reading is ever offerable, taps are `readNow + refusedSecure + refusedSecureUnknown`.

This guard is not a substitute for §5.1. It narrows one case; §5.1 is why there is no
speculative upload to narrow in the first place.

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
| `Bar/screen-context/harness/memory.swift` | The §2.3 probe. `phys_footprint` via `task_info(TASK_VM_INFO)` over all 30 bar images in one process, one image alive at a time, one reused request. Reports its deployment, `supportedComputeStageDevices` per request, and the ledger breakdown (`internal`, `external`, `graphics`, `neural`, `neural-nofootprint`, kernel footprint peak) — which is what §2.3.1 needed and the first version of the probe could not answer. `PASSES=` and `SAME_IMAGE=` produce the §2.3.2 growth table. Exits non-zero on a missing image, a failed Vision call, a `supportedComputeStageDevices` that errors, or a `task_info` that will not answer. Compiles unchanged for `arm64-apple-ios`, which is how it becomes the device measurement §1.4 asks for. |
| `Bar/screen-context/harness/run-memory.sh` | Builds both deployments, requires a booted simulator, prints the compute-device table and **asserts that `VNDetectTextRectanglesRequest` is cpu-only on both**, and prints the labelled peak table. That assertion replaced the previous ANE-framework assertion, which asserted a true fact that explained nothing. Fails rather than skips at every step. `SCALES="1.0 0.5 0.25"` runs the resolution sweep, `CONFIGS=fast` narrows it. |
| `Bar/screen-context/harness/frame-hash.mjs` | The §5.5/§6 probe. Renders every corpus scene seven times — as-is, with every message's glyphs substituted inside its own script, with only the newest message's glyphs substituted, with only the status-bar clock and the header presence line changed, and three more with *our own* keyboard on screen and the AI result panel loading (shimmer phase 0.10, phase 0.60, and the newest message's glyphs changed under it) — then reports, per crop band and per fingerprint value, how many near pairs it fails to separate and how many changes it wrongly separates, with and without our keyboard up. All four columns must be zero in the pair that applies, and §5.5.1 says which band that is. `KEEP=1` leaves the rendered frames. |

### Create

| Path | Contents |
|---|---|
| `AIKeyboardBroadcast/Info.plist` | `NSExtensionPointIdentifier = com.apple.broadcast-services-upload`, `RPBroadcastProcessMode = RPBroadcastProcessModeSampleBuffer`, `NSExtensionPrincipalClass = $(PRODUCT_MODULE_NAME).SampleHandler`. Verified against Xcode's own template at `iPhoneOS.platform/.../Broadcast Upload Extension.xctemplate/TemplateInfo.plist`. Needs a `membershipExceptions` entry, as `AIKeyboardExtension/Info.plist` has. |
| `AIKeyboardBroadcast/AIKeyboardBroadcast.entitlements` | `com.apple.security.application-groups` = `group.com.nitai.aikeyboard` |
| `AIKeyboardBroadcast/SampleHandler.swift` | `final class SampleHandler: RPBroadcastSampleHandler`. Overrides `broadcastStarted(withSetupInfo:)`, `broadcastPaused()`, `broadcastResumed()`, `broadcastFinished()`, `broadcastAnnotatedWithApplicationInfo(_:)`, `processSampleBuffer(_:with:)`. Owns the heartbeat timer, a `MemoryGovernor` and a `ScreenReadService`, and nothing else. |
| ~~`AIKeyboardBroadcast/CaptureLoop.swift`~~ | **Not written, and not missing.** The throttle/settle/budget state machine this row specified has no state left to hold: the throttle is one `ContinuousClock` comparison in `sampleVideo`, the settle rule went with T2 (§5.1), and the budget was deleted with `refusedBudget`. What remained — "is this frame the one that answers a raised request" — is `ScreenReadService.claim(intent:identity:capturedAt:)`, in `AIKeyboardShared`, where `ScreenReadServiceTests` can drive it off-device. |
| `AIKeyboardBroadcast/FrameScaler.swift` | `struct FrameScaler` — vImage. One preallocated `vImage_Buffer` per output size, created at `broadcastStarted` and reused. Scales planes *before* colour conversion when the source is 420f, so no full-size ARGB intermediate is ever allocated. |
| `Packages/AIKeyboardCore/Sources/AIKeyboardShared/MemoryGovernor.swift` | `final class MemoryGovernor` over `task_info(TASK_VM_INFO)`: `footprintMB()`, `begin()` (measures this session's baseline and sets the watermark from it), `observe()` (one sample, reporting the transition so the shared page is written only when the answer flips) and `isRefusing`. Shares the implementation with `memory.swift` by eye, not by import: the probe must stay outside every target. **In `AIKeyboardShared` rather than in the extension target**, against §11's original placement, because `AIKeyboardCoreTests` cannot reach an app extension and a self-protection rule nobody has run is not one. |
| `Packages/AIKeyboardCore/Sources/AIKeyboardShared/CaptureChannel.swift` | `enum CaptureChannel` (container URLs), `struct CaptureStatus` and `struct CaptureIntent` (fixed C layouts), `final class SharedPage<T>` (the mmap + seqlock wrapper). `CaptureStatus` is **256 bytes**, not 128: §6's identity value is a 32-byte SHA-256 alongside the session UUID, the three timestamps and the counters. It carries `currentFrameIdentity` **and** `currentFrameSampledAt` **and** `lastFrameAt` **and** `paused` — §6 needs all four and a design that ships three of them has the stale-reading bug. |
| `Packages/AIKeyboardCore/Sources/AIKeyboardShared/FrameFingerprint.swift` | `struct FrameFingerprint { let identity: FrameIdentity; let changeScore: Double }`, the 32x64 greyscale reduction, and the crop band. **Two values from one reduction and they have different jobs**: `identity` is `SHA256` of the 2,048 bytes and answers "is this the same screen" for §6 condition 4; `changeScore` is a perceptual distance over a 64-bit difference hash of the same bytes and answers "has it stopped moving" for the settle gate, and nothing else. §5.5 has the measurement that forced the split. |
| `Packages/AIKeyboardCore/Sources/AIKeyboardShared/ScreenReadingRecord.swift` | `struct ScreenReadingRecord: Codable, Sendable` — `sessionID`, `requestSequence`, `frameIdentity`, `capturedAt`, `readAt`, `provenance`, and the `ScreenReading` fields. Text and hashes only, by construction; no reduction, no thumbnail, nothing that renders. |
| `Packages/AIKeyboardCore/Sources/AIKeyboardShared/ScreenContextEndReason.swift` | `enum ScreenContextEndReason: UInt8` — `.none`, `.stopped`, `.lost`, and that is the whole list. The five `RPRecordingErrorCode` cases this row used to specify were unwritable: `broadcastFinished` takes no argument, `RPBroadcastSampleHandler` has no callback carrying an `NSError`, and `finishBroadcastWithError:` is a method the extension *calls*, whose error reaches an `RPBroadcastController` this app does not have (broadcasts start from `RPSystemBroadcastPickerView`). So the capture process is told *that* the broadcast ended and never why, and `.stopped` does not claim a cause. `.lost` is still the inferred one, from a stale heartbeat with no recorded end. |
| `Packages/AIKeyboardCore/Sources/AIKeyboardCore/SecureField.swift` | The §3.3.1 guard. Takes `(secure: Bool?, contentType: UITextContentType??)` rather than the proxy, so its whole truth table is unit-testable without a host app, including the two cases the naive spelling gets wrong. |

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
| `.../AIKeyboardCore/KeyboardController.swift` | `requestScreenRead()` consults `SecureField.permitsRead(secure:contentType:)` (§3.3.1) and then bumps `intent.readNow`; Reply awaits a record with a matching sequence, with a 12 s timeout mapping to a new `AIActionError` case. `viewDidAppear`/`viewWillDisappear` drive `intent.keyboardVisible`. |
| `.../AIKeyboardCore/SharedStore.swift` | Add `screenContextDailyReadBudget: Int`. **Do not** add a speculative-reads flag. Fix the doc comment at line 144, which says only text leaves the device (§5.2). |
| `AIKeyboard/Main/ScreenContextView.swift` | Rewrite step 2 at line 205 and check step 3 at line 210 (§5.2). Host `RPSystemBroadcastPickerView` with `preferredExtension` set to the broadcast bundle ID and `showsMicrophoneButton = false` (both verified, `RPBroadcast.h`). Show live `CaptureStatus`, the budget, and the restart button. |
| `AIKeyboard.xcodeproj/project.pbxproj` | New target. Files inside `AIKeyboardBroadcast/` are picked up by `PBXFileSystemSynchronizedRootGroup` once the group exists, but the target itself is a real `.pbxproj` edit. |
| `Scripts/prove-app-group.sh` | Add check 5: two processes mmap `channel/status.bin` and each observes the other's write. |
| `README.md` | **Add** a paragraph; do not replace the existing measured ones (§5.3). |

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
the phone. §3.3.1's guard narrows the password-field case a little and, because the trait
is optional and may be `nil` everywhere, may narrow nothing at all — which is exactly why
it is not allowed to be the argument.

And the narrowing that *would* work is circular. To decide whether it is safe to upload
this screen, you would have to know what is on it. Knowing what is on it is the read.
There is no cheaper signal available on this deployment:

- `broadcastAnnotatedWithApplicationInfo:` gives the **first** app only, and only from a
  Control Center start (§7, verified). Not a live signal.
- There is no public API on iOS for the frontmost bundle identifier from any extension.
- The frame fingerprint cannot classify a screen. §5.5 measures what it *can* do, which is
  tell one screen from another, and that is all it can do.
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
on the facts: `README.md` lines 116-127 are accurate today and are the most carefully
measured paragraph in the file. The claim that needs fixing lives in three other places,
and two of them are about to become false for a new reason.

| Where | Text | Status |
|---|---|---|
| `AIKeyboard/Main/ScreenContextView.swift:205` | "Each frame goes through **on-device** text recognition. The frame is overwritten by the next one and never saved." | **False under this design.** The recognition is not on-device. The second sentence stays true and stays. |
| `AIKeyboard/Main/ScreenContextView.swift:210` | "The keyboard receives the recognised message, not an image, and only when you tap Reply." | **True, and it stays true only because T2 is deleted.** This sentence is the reason §5.1 is not a close call: the product already promises it. |
| `Packages/.../SharedStore.swift:144` | "Only the text read off the frame ever leaves the device." | **Already false**, since `CloudScreenReader` existed — it posts a JPEG. Not a README problem; a code-comment problem. |
| `Packages/.../Models.swift:149-151` | "the product promise is that pixels are overwritten and never kept, so the only thing that travels is the text that was read off them" | **Half false.** Overwritten and never kept: true. Only text travels: false. |
| `Packages/.../ScreenContextSession.swift:90-96` | "The frame is read and dropped; only the text survives the call, which is the promise the Screen Context screen makes." | **Half false**, same split. |

**All five are fixed as of Phase 6**, and the copy pass found three more the table missed.
`ScreenContextView`'s step 2 now says the reading happens in the cloud and that one
shrunken picture goes out per tap. The three new ones: the "Use the cloud for replies"
toggle promised that switching it off would keep screen reading on the device, and no code
read the setting at all — it is deleted, property and all, rather than made to work,
because §1.1 is the argument against the thing it promised. The limits list asserted that
protected content blacks itself out; that is R13, unverified, and it now says so in the
product rather than only in this document. And the Reply panel's "Start screen context"
button started the *scripted sample*, which is the worst of the three: a button labelled
with a privacy-relevant action that did something else. It is words now.

The accurate claim, which each clause maps to code:

> The screen is never stored. One frame at a time lives in a single buffer inside the
> capture process and is overwritten by the next; nothing on disk, in the shared
> container, or in a backup ever contains a picture of your screen. A frame leaves the
> device only when you tap Reply, and what comes back is text.

The buffer is a `vImage_Buffer` preallocated at `broadcastStarted`; the container holds
two fixed-layout binary pages and one JSON file whose type has no image field; the frame
leaves only inside `CloudScreenReader.read`, only on the serial read queue, only with a
matching `intent.readNow` sequence. The 2,048-byte greyscale reduction §5.5 needs is
computed, hashed and dropped inside `processSampleBuffer`; it is never written to the
container, because at 32x64 it is a bad picture but it is still a picture, and the sentence
above says nothing on disk contains one.

### 5.3 What the README needs, and what it must keep

`README.md` lines 116-127 stay. They are the on-device/cloud split earned with measured
numbers (30 languages, 100% English recall, 13% Hebrew, the coverage/confidence gate), and
that split is still true of `RoutedScreenReader` and still true of the in-app playground
path, where the containing app holds the frame and no extension cap applies.

Lines 129-133 stay too, and they are now the load-bearing paragraph rather than a caveat:
they are §1.1, already written and already correct.

What needs rewriting is lines 134-138, which pose this document's question as open and
frame it as *memory first*:

> Two things are still open and are being measured rather than argued: whether Vision can
> run at all inside the ~48 MB a keyboard extension gets or the 50 MB a broadcast
> extension gets, and whether the privacy gain of keeping eight English frames on the
> device is worth three points of accuracy. If the answer to the first is no, the second
> is moot and every screen read goes to the cloud.

They become:

> The order of those questions was backwards. The accuracy one is answered above and it is
> answered on iOS, so in the ReplayKit capture flow every screen read goes to the cloud,
> English included, and it goes only when you tap Reply. The memory question is still open
> and is stranger than it looked. Over the 30 screens in `Bar/screen-context/`, in one
> process, `VNDetectTextRectanglesRequest` alone peaks at 9.9-11.3 MB on the iOS
> Simulator and 66.7-72.6 MB on macOS 26.5.1, and `.fast` recognition at 18.1-22.9 MB
> against 84.6-95.1 MB. Both platforms ship the same Vision model assets and both report
> the same compute device for these two requests: `[cpu]`. The gap is where the kernel
> charges the memory, not what runs; macOS puts
> ~63 MB on the footprint ledger jetsam reads, and the iOS build maps ~11 MB file-backed
> and charges the ledger ~5 MB. Which of those a phone does is unknown, and there is no
> device measurement here. `Bar/screen-context/harness/run-memory.sh` re-takes all of it.

That keeps every measured claim the README already earns, puts the answered question first,
and does not invent a mechanism for the unanswered one. The mock-to-real table's
`MockScreenContext` row also needs the ReplayKit route marked as designed-but-unbuilt
rather than absent.

### 5.4 What the App Group actually holds

- `channel/status.bin`, 256 bytes: session UUID, heartbeat, last frame time, current frame
  identity (32-byte SHA-256) and the time it was sampled, paused flag, frames seen, reads
  fired, reads the *producer* refused by reason, last end reason, degraded flag.
- `channel/intent.bin`, 64 bytes: keyboard-visible flag and its timestamp, read request
  sequence and its timestamp, and the two secure-field counters of §3.3.1 — which are here
  rather than on the status page because the keyboard is the process that refuses and the
  process that may write this page.
- `channel/reading.json`: `ScreenReadingRecord`. Sender, message, language, identity,
  timestamps. Deleted on `broadcastFinished()` and on session start — and, because a jetsam
  kill fires neither, by `CaptureChannel.sweep()` from the containing app whenever the
  producer that wrote it is no longer beating. Nothing in the container is allowed to outlive
  the session it describes just because the process that owned it was killed.

And what is **not** in the container, swept on every app launch by the same call: channel
directories no shipping code opens. `channel-com.nitai.aikeyboard/` and
`channel-com.nitai.aikeyboard.keyboard/` were left there by an experiment that rooted the
channel per process. Unlinking those is safe precisely where unlinking `channel/status.bin`
would not be — nothing has them mapped — which is why `clear()` still zeroes the live pages
in place.

**The frame identity is a SHA-256 of the 2,048-byte reduction, and that is a privacy
choice as well as a matching one.** The previous version stored a 64-bit perceptual hash
and defended it as safe *because it is uninformative*. That defence was the problem: an
uninformative value is also a weak discriminator, which is what §5.5 went and measured.
The replacement is better on both counts at once. A cryptographic hash of the reduction
supports exactly one operation — "are these the same reduction" — whereas a perceptual hash
also supports "are these *similar*", which is the operation that lets a value be clustered
or matched against a corpus of known screens. Trading the perceptual hash for a
cryptographic one buys discrimination and gives up a linkability capability at the same
time. It is still a per-screen identifier, it still never leaves the device, and there is
still no reason to send it. Say so in the code.

The 64-bit perceptual hash does not disappear; it is confined to `changeScore`, the settle
detector, where "uninformative" is the correct property and where nothing depends on it
being unique.

### 5.5 The band the fingerprint is taken over, measured

The previous version cropped two bands before the reduction — the status bar (top ~6.5%)
and "the bottom 45% where our own keyboard sits" — and justified them by analogy: without
the first, the clock invalidates every reading once a minute. The first band was right and
cited `VisionScreenReader.Band.statusBar`. **The second band was invented.** It has no
counterpart in `VisionScreenReader.Band`, whose `composer` is 0.085, and it removed 45% of
the frame from the region that decides identity.

`Bar/screen-context/harness/frame-hash.mjs` measures what that costs. For each of the 30
corpus scenes it renders the scene, a twin with every message's letters substituted inside
its own script (same character count, same word breaks, same times, same bubble geometry,
every glyph different), a variant with only the *newest* message's letters substituted, and
a variant where only the status-bar clock and the header presence line changed. Then, per
band and per value:

| Band removed | Value | misses | false invalidations |
|---|---|---|---|
| none | `sha256` of the reduction | 0/29 | **30/30** |
| none | 64-bit dHash | **10/29** | 1/30 |
| none | 256-bit dHash | 0/29 | **13/30** |
| top 6.5% (status bar) | `sha256` | 0/29 | **19/30** |
| top 6.5% | 64-bit dHash | **6/29** | 3/30 |
| top 6.5% | 256-bit dHash | 0/29 | **11/30** |
| top 6.5% / bottom 8.5% (status + composer) | `sha256` | 0/29 | **19/30** |
| top 6.5% / bottom 8.5% | 64-bit dHash | **10/29** | 2/30 |
| top 6.5% / bottom 8.5% | 256-bit dHash | 0/29 | **15/30** |
| top 6.5% / **bottom 45%** (the previous design) | `sha256` | **23/29** | **19/30** |
| top 6.5% / **bottom 45%** | 64-bit dHash | **23/29** | 3/30 |
| top 6.5% / bottom 45% | 256-bit dHash | **23/29** | **13/30** |
| **top 14% / bottom 8.5% (`VisionScreenReader.Band`)** | **`sha256`** | **0/29** | **0/30** |
| top 14% / bottom 8.5% | 64-bit dHash | **10/29** | 0/30 |
| top 14% / bottom 8.5% | 256-bit dHash | 0/29 | 0/30 |

*misses* counts scene pairs that differ only in the newest message's glyphs and produce the
same value. §6 condition 4 is exact equality, so every miss is a reading that stays
offerable across a conversation switch — the precise failure this design exists to prevent.
*false invalidations* counts frames where nothing but the clock and the presence line moved
and the value moved with them; each of those retires a good reading and buys a needless
cloud read. `sl-05` is excluded from the miss column and counted separately: its newest
message is drawn under the host keyboard, so the two renders are byte-identical and no
fingerprint of any width can separate them. That is a property of the screen, and the
correct behaviour there is the refusal `VisionScreenReader` already gives.

Three things this settles:

1. **The old bottom band was the primary defect, and it was not a close call.** Cropping
   the bottom 45% removes the newest message from the fingerprint entirely: 23 of 29 pairs
   that differ only in the newest message hash identically, and widening the hash from 64
   to 256 bits does not fix a single one of them. A band that excludes the thing the
   reading is *about* cannot be rescued by a better hash.
2. **The correct band is the one `VisionScreenReader` already reads.** `Band.navigationBar
   = 0.86` and `Band.composer = 0.085` in Vision's bottom-up coordinates are the top 14%
   and the bottom 8.5% here. Cropping the navigation bar is not cosmetic: it is where the
   presence line lives, and the presence line changes on its own. Without that band
   removed, a chrome-only change moves an exact hash on 19 of 30 frames. With it removed,
   on 0 of 30. The measurement extends this section's original argument about the clock to the
   thing sitting directly under it, which the previous version missed. The pleasing
   consequence is that the fingerprint now covers exactly the region the reading is taken
   from — the same band `VisionScreenReader.interpret` filters message lines to.
3. **64 bits is not enough even over the right band.** 10 of 29 pairs collide. The
   256-bit dHash and the SHA-256 both reach 0/29 and 0/30; the SHA is chosen for §5.4's
   reason, and because the miss column is what matters and an exact hash cannot regress on
   it.

### 5.5.1 And our own keyboard is not part of "which screen is this"

The table above was taken over frames rendered with the **host's** keyboard, or none. That
is not the state any real reading is ever measured in. A reading exists only because the
user tapped Reply on *our* keyboard, so our keyboard is on screen for the whole five-second
read — with `AIResultPanel.loading` repainting three shimmer lines at `workingPhase += 0.03`
every 16 ms. On an iPhone 17 Pro our keyboard at its tallest is 365 pt of 874 pt, which is
**41.8% of the fingerprint band**, and SHA-256 moves on a one-level change in any of the 2,048
samples. (292 pt was the keyboard of the day this was written, before the action row and the
banner; `FrameReduction.Band.maximumOwnUI` is the 368 pt line it may not cross.)

So `frame-hash.mjs` now renders three more variants per scene: the scene with our keyboard
up and the result panel loading at shimmer phase 0.10, the same at phase 0.60, and the
newest message's glyphs substituted under it. Two more columns, asking the same two
questions of the deployed state — `own miss` is a conversation switch our panel is sitting
over, `own false` is our own shimmer and nothing else:

| Band removed | Value | miss | false | own miss | own false |
|---|---|---|---|---|---|
| top 6.5% / bottom 45% | `sha256` | **23/29** | **19/30** | 3/29 | 0/30 |
| top 6.5% / bottom 8.5% | `sha256` | 0/29 | **19/30** | 0/29 | **30/30** |
| top 14% / bottom 8.5% (§5.5's answer) | `sha256` | **0/29** | **0/30** | 0/29 | **30/30** |
| top 14% / bottom 8.5% | 64-bit dHash | **10/29** | 0/30 | 4/29 | **25/30** |
| **top 14% / bottom 33.4% (ours excluded)** | **`sha256`** | 20/29 | **0/30** | **0/29** | **0/30** |
| top 14% / bottom 40% (`Band.maximumOwnUI`) | `sha256` | 20/29 | 0/30 | **0/29** | **0/30** |

**30 of 30 is the shipping blocker this found**, and it was live: the frame was uploaded,
the cloud call was spent, the record landed, and §6 condition 4 called it `.superseded`
because our own shimmer had moved. Twelve seconds after the tap the user was told nothing
answered the request to read the screen — non-deterministically, which is worse than always
failing.

The fix is one band, chosen per frame from a number only the keyboard can know. It publishes
the fraction of the screen it covers in `CaptureIntent.ownUIHeightPermille`; the producer
turns that into a crop with `FrameReduction.bottomCrop(ownUI:)` and reduces the frame
without it. Four things this rests on:

- **It costs no host content.** While our keyboard is up, everything below its top edge
  *is* our keyboard. The 20/29 in the *miss* column of the last two rows is not information
  lost: those bands are only ever used on a frame our keyboard is on, and the column that
  applies there — `own miss` — is 0.
- **The threat is untouched.** Condition 4 is still exact equality against the newest
  sampled frame, and `own miss` 0/29 is that condition measured in the deployed state: a
  user who switches conversation under our panel is still refused.
- **The height is the *tallest* form, not the current one.** The context strip appears and
  disappears with the capture session, including mid-read, and a band that moves retires a
  reading exactly as a conversation switch does.
- **The claim is bounded.** It is a number one process reads out of a page another writes.
  Below `Band.bottom` it is ignored; above `Band.maximumOwnUI = 0.40` it is clamped, and
  that cap is the last row of the table rather than a guess. Past it lies the 45% band and
  23 of 29 missed switches.

`Bar/screen-context/harness/fingerprint.swift` scores both configurations against the
shipping Swift, and carries a witness check: over the band that does *not* exclude our
keyboard, our own shimmer still moves the identity on 30/30 scenes. A harness that cannot
fail proves nothing, and that is the number that says this one can.

The reduction stays 32x64 greyscale, 2,048 bytes, as §2.2 budgets, and the margin at the
chosen band is not thin. Over the 29 separable pairs, the number of the 2,048 samples that
change runs from 30 (minimum) through a median of 132, and the largest single-sample change
is never smaller than 18 grey levels. Nothing here sits on a quantisation edge.

### 5.6 Option (b), analysed as asked, and still rejected

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

So (b) *can* be honest. It is rejected on the ground that has not moved: the only thing (b)
buys is letting the keyboard run `RoutedScreenReader` on device, and §1.1 measures that
path scoring *below* cloud-only on iOS, with three of its eight answers wrong. (b) would
pay six real obligations for a capability that is not better.

The memory ground that used to sit alongside it is withdrawn along with the ANE
explanation. §2.3 no longer establishes that Vision cannot fit in a keyboard extension; it
establishes that two non-device deployments disagree by 6x for reasons of accounting. If a
device measurement comes back cheap, this section becomes the checklist for (b) and §1.1 is
the thing that still has to be answered first.

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

| # | Condition | Kind | Catches |
|---|---|---|---|
| 1 | `now - status.heartbeatAt <= 3 s` | liveness | the extension process is dead, including a jetsam kill that fired no callback |
| 2 | `status.paused == 0` and `now - status.lastFrameAt <= 2 s` | liveness | the process is alive but frames have stopped: `broadcastPaused()`, a stalled delivery path, a wedged handler |
| 3 | `status.currentFrameSampledAt >= record.readAt` | liveness | **the reading has been confirmed against a frame observed after it completed** |
| 4 | `record.frameIdentity == status.currentFrameIdentity` | **content** | the user scrolled, switched conversation, switched app, or a new message arrived |
| 5 | `now - record.capturedAt <= 20 s` and `record.sessionID == status.sessionID` | timer | intent moved even though the pixels did not; the broadcast was restarted since the reading |

Fail 1 and the strip renders `.ended`. Fail 2 and it renders `.paused`. Fail 3 and it
renders the loading state, because the reading is not stale, it is merely unconfirmed.
Fail 4 or 5 and it renders the pre-tap offer. **The strip has no stale-but-shown state at
all.**

**Amended when Phase 6 was built: condition 2 needed splitting.** A session that has begun
and delivered no frame yet fails it in exactly the same way a stalled one does, so the
first three seconds of every session — the picker's own countdown — rendered as "paused",
which reads as a fault. `CaptureFreshness` therefore returns `.starting` when
`lastFrameAt` has never been written and `.paused` only once a session that *had* frames
stops having them. The test is a fact about the page rather than a new threshold, and
`CaptureFreshnessTests` pins both halves.

**Condition 4 is the only content-identity condition in the table**, and the "kind" column
is there so that stays visible. 1, 2 and 3 all answer "is the producer alive and has it
looked recently"; a wedged process and a switched conversation are different failures and
only condition 4 sees the second. 5 is a timer with a guessed constant (§6.2). So the whole
defence against *the wrong conversation* is one equality test, and the value on both sides
of it has to be good enough to carry that alone. §5.5 is the measurement that makes it so,
and it changed two things: the band the value is computed over, and the value itself.

### 6.1 Condition 3 is the one the first revision added, and it is the one that mattered

Conditions 1, 4 and 5 were in the original version and they do not close the hole. The
hole is this: `status.currentFrameIdentity` is only meaningful if it is the identity of a
frame the extension *observed*. If the read runs inline in `processSampleBuffer`, no frames
are observed for the 5.3 s the read takes, so the identity is frozen at the value of the
frame being read — while the heartbeat, on its own 1 Hz timer, keeps ticking. A user who
switches conversation mid-read then gets a record whose identity matches a
`currentFrameIdentity` that has not been updated since before the switch. Conditions 1, 4
and 5 all pass and only the admittedly-guessed 20 s backstop stands between the user and a
reply written about somebody else's message. `broadcastPaused()` opens the identical
window from the other direction.

Condition 3 closes it by refusing to treat the identity as evidence until it has been
*re-observed* after `record.readAt`. Condition 2 closes the pause variant. And §3.1
is what makes this cheap rather than a 5.3 s dead zone: because the read is off the
delivery path, fingerprinting continues throughout, so `currentFrameSampledAt` advances
every 250 ms and confirmation normally lands within one sample of the read returning.

Two implementation rules follow and both are testable off-device:

- `status.currentFrameIdentity` and `status.currentFrameSampledAt` are written **together,
  in one seqlock transaction, on every sampled frame**, and by nothing else. An identity
  without its timestamp is a lie waiting to happen.
- The heartbeat writes `heartbeatAt` and **never touches** `currentFrameIdentity`,
  `currentFrameSampledAt` or `lastFrameAt`. The heartbeat proves the process is alive.
  `lastFrameAt` proves delivery is alive. They are different failures and conflating them
  is how a wedged handler looks healthy.

### 6.2 The residual hole condition 4 cannot close

There is one and it should be named rather than hidden: **a frame whose newest message is
drawn under the host keyboard has no pixels to change.** `sl-05` in the corpus is exactly
this, and `frame-hash.mjs` reports its two renders as byte-identical. If the user switches
to a conversation whose visible content is the same and whose only difference is under the
keyboard, no fingerprint of any width separates them, because there is nothing to separate.

This is bounded rather than solved. It is bounded because the content under the keyboard is
also content `CloudScreenReader` cannot read — the reading itself would be about the
visible part — and because condition 5's 20 s cap still applies. It is not solved and no
change to the fingerprint solves it. The right move if it ever shows up in practice is
`VisionScreenReader`'s: refuse rather than answer.

### 6.3 The backstop is still a guess

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

Move 3 is what shipped: the strip names the sender and never the app, `ScreenContextStrip`
renders no SF Symbol for one, and Reply's own subtitle in the AI menu says "To Maya" rather
than "From WhatsApp". `ScreenContext.appName` and `appIcon` still exist as strings because
the in-app sample fills them, and the record that crosses the channel leaves both empty —
so no code path can print an app name it did not read off the screen.

Three moves, in order of confidence:

1. **Store what the header gives, use it where it is true.** Capture the bundle ID into
   `CaptureStatus.firstAppBundleID` when it arrives and show it only in the app's Screen
   Context screen, as history ("started while you were in WhatsApp"). Never as a live
   label, and never as an input to any decision about whether to upload.
2. **Get the app from the reading, which already looks at the pixels.** Add an `app` field
   to `ScreenPrompt.fields`. It must go **last, after `language`** — the repo's field-order
   rule is measured and load-bearing (splitting `script` from `language` is worth 8 points
   of keyboard language, 22/30 against 30/30, and enumerating first is worth 2 of sender
   and 3 of language — see `Bar/screen-context/ablation/`), so nothing before it may move.
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

Whatever the outcome, `.ended` is a first-class state with a way back, not an absence.

**The reason it carries is thinner than this section assumed.** "Screen context stopped
because you took a call" is indeed a different message from "…because it ran out of
memory" — and an upload extension is told neither. See §11's row for
`ScreenContextEndReason`: the only two endings anything can produce are "the broadcast
finished" and "the heartbeat stopped". The second is the bug report, and it is the one a
jetsam kill leaves. Naming a cause the platform never supplied is what §8.4 rule 1 was
doing, and it is withdrawn.

### 8.4 Two rules Phase 6 had to add, and they are not in §8.2

Built as specified, §8.2 says two things the product should not say.

1. ~~**`.userStopped` is not an ending to report.**~~ **Withdrawn.** The rule was: a strip
   that renders every ending says "screen context stopped" for ever after the user stopped
   it on purpose, so `ScreenContextSession` maps that one reason to `.off`. It needed the
   capture process to know the user was the one who stopped it, and it does not.
   `broadcastFinished()` takes no argument, and `RPBroadcastSampleHandler` has no callback
   anywhere that carries an `NSError` (see §11's row for `ScreenContextEndReason`), so
   writing `.userStopped` there was a claim nothing had checked — and the mapping then
   erased the strip whenever iOS ended a session for a call or the lock button, which is
   the one thing §8.2 exists to forbid. Now: `.stopped` names no cause, and every ending is
   reported. Redundant after a deliberate stop beats silent after an involuntary one. What
   §8.2 promised about *which* reason it was is a promise the platform does not let this
   app keep, and the Screen Context screen says so instead of claiming it.
2. **An ending decays.** A page whose producer died is `.ended(.lost)` for ever, and a
   strip still offering to restart yesterday's session is crying wolf. The session reports
   an ending if it watched that session run *or* the heartbeat stopped within the last ten
   minutes. The first half is exact; **the ten minutes is a guess** in the same class as
   §6.3's twenty seconds, chosen to cover the case §8.2 exists for — a jetsam kill while
   the user is in another app, so the consumer never saw the session alive — and would be
   set properly by instrumenting the gap between a kill and the next keyboard appearance.
   A reboot needs neither rule: `CaptureClock` restarts below every timestamp in the page
   and `CaptureClock.elapsed` reports a future timestamp as infinitely old.

Phase 6 also kept the scripted timeline §4 said would go, because the in-app playground and
the UI walkthrough drive it and there is nothing else to drive on a machine with no
`replayd`. It is not a peer of the real thing: `ScreenContextSession.source` names which
source published the state, a real session cancels the script rather than racing it, and
nothing paints a recording indicator over the sample.

---

## 9. Build sequence

**Phase 0 — settle the numbers that decide the design (device required, currently
blocked).** The probes are landed: `memory.swift`, `run-memory.sh` and `frame-hash.mjs`.
What is left needs an iPhone, and the paired one is offline:

- **R2/R2b, the ceilings.** Allocate in 1 MB steps in each extension and log
  `phys_footprint` until it dies. The last logged value is the answer, once for the
  broadcast extension and once for the keyboard.
- **R3, Vision on a device.** Build `memory.swift` for `arm64-apple-ios` and run it as a
  device unit test over all 30 images. Record not just the peak but the ledger breakdown,
  because §2.3.1's open question is *where the bytes are charged*, not how many there are.
  This is the one measurement that decides §1.3.
- **R1, the frame.** Log `CVPixelBufferGetPixelFormatType`, width, height and inter-frame
  interval from `processSampleBuffer` for 60 s.
- **R7, the network.** A `URLSession` request from `broadcastStarted`, logged.

None of Phases 3 onward is safe to size without R1, R2 and R7. Phases 1, 2 and 6 do not
depend on them and can proceed.

**Phase 1 — the package split, no behaviour change.**
Create `AIKeyboardShared`, move the Foundation-only types, add `@_exported import`.
`AIKeyboardCoreTests` (including `BackendTransportSuiteTests`) and
`Scripts/prove-app-group.sh` must pass untouched. If they don't, the split is wrong.

**Phase 2 — the channel and the fingerprint, provable before anything captures.**
`CaptureChannel`, `SharedPage`, `CaptureStatus` (256 bytes, with all four freshness
fields), `CaptureIntent`, `ScreenReadingRecord`, `FrameFingerprint`. Unit tests for the
seqlock, and for the fingerprint against §5.5: the crop band is the
`VisionScreenReader.Band` one and the identity is the SHA of the reduction, so a test can
pin both by asserting that two corpus frames differing only in their newest message produce
different identities. Add check 5 to `prove-app-group.sh`: two processes, one mmap'd page,
each sees the other's write. Do not proceed until that check passes on a real keyboard
extension, because everything above it assumes it.

**Phase 3 — the shutter, with no reading in it. This is the budget gate.**
The `AIKeyboardBroadcast` target, `SampleHandler`, `FrameScaler`, `MemoryGovernor`. It throttles, fingerprints, heartbeats, and publishes `CaptureStatus` —
and calls no reader at all. Run it for ten minutes against WhatsApp on a device with a
memory graph attached, and **record the baseline**, which §2.4 currently guesses at 20 MB.
Gate: if baseline + one mapped frame + the downscale destination exceeds 30 MB, there is
no room for TLS and the design changes here, before any reading code exists. `MemoryGovernor`
already sets its watermark from the baseline it measures at `broadcastStarted`, and logs
both, so this phase reads the number out of the log rather than editing a constant; what it
still has to settle is the 50 MB ceiling (R2) and the 10 MB read reserve (R7).

**Phase 4 — the on-device question, answered on the right hardware.**
This phase used to re-run `coverage.swift` with `.fast` on macOS. That measured the wrong
quantity (accuracy, not memory) on the wrong deployment (`run-reader.sh` builds with
`xcrun -sdk macosx`, and `.claude/CLAUDE.md` records that macOS and iOS Vision give
different verdicts on these exact images). Replaced with:

> Run `Bar/screen-context/harness/memory.swift` **on a device**, built for
> `arm64-apple-ios`, all 30 images, all configurations, two runs per configuration, plus
> one `PASSES=2` run. Confirm the deployment line reads `iOS device`, record the
> compute-device line, and record the ledger breakdown. Peak under ~30 MB for `.fast` +
> rectangles removes the memory objection and sends this back to §5.6. Anything near the
> macOS figure confirms this design's default.

The accuracy case has to be re-won separately and it is the harder one:
`AIKeyboardCoreTests/ScreenContextBarTests.swift` measures the routed path scoring below
cloud-only on iOS, with three of its eight on-device answers wrong. A cheap memory result
does not touch that.

**Phase 5 — reading, in the shutter.**
`CloudScreenReader` on the serial read queue inside the broadcast extension, gated by
`MemoryGovernor`, T1 only. R5 is settled ahead of this phase (§2.2.1): the downscale costs
no sender, message or language accuracy, so the 804x1748 fallback and its 2.4 MB are not
needed and Phase 3's baseline does not have to leave room for them.

**Phase 6 — the consumer.**
`ScreenContextSession` rewritten as a channel consumer. The §6 freshness gate, with tests
for **all five** conditions, including the mid-read conversation switch and the
`broadcastPaused()` window that condition 3 exists to catch, and including §6.2's
keyboard-occluded case as a known-unresolvable. `.ended` and `.paused` in
`ScreenContextState` and in the strip. The strip stops naming apps and gains the pre-tap
offer state.

**Phase 7 — the budget, the secure-field guard and restart.**
Daily and session read budgets in `SharedStore` and their UI. `SecureField` with its full
truth table under test, including `nil` and `UITextContentType??`'s two nils. R14 becomes a
counter: ship both `refusedSecure` and `refusedSecureUnknown` and read them off the first
device run. If `refusedSecureUnknown` equals the tap count, the trait is never populated
through the proxy and a different signal is needed — the default does not flip. R8 and R9
on device, then whichever restart path survives. No speculative reads, now or later,
without the signal §5.1 names.

**Phase 8 — the docs that are now wrong.**
`README.md` lines 134-138 are replaced per §5.3 and lines 116-133 keep. The mock-to-real
table's `MockScreenContext` row. The five stale privacy comments in §5.2.
`.claude/docs/architecture.md`'s directory map and data flow. And a `.claude/CLAUDE.md`
gotcha — but not the one the previous revision drafted, which asserted the ANE explanation
this revision retracts:

> **Vision's memory cost differs 6x between macOS and the iOS Simulator, and nobody here
> knows what a phone does.** Over the 30 bar screens in one process, peak `phys_footprint`
> for `VNDetectTextRectanglesRequest` alone is 66.7-72.6 MB on macOS 26.5.1 and
> 9.9-11.3 MB on the iOS Simulator; `.fast` is 84.6-95.1 against 18.1-22.9. It is not the
> Neural Engine: `supportedComputeStageDevices` reports both requests as `[cpu]` on **both**
> deployments, and only `.accurate` lists `ane`. It is not a bigger model either: the two
> platforms ship the same Vision Espresso assets at the same sizes. The difference is
> accounting — macOS charges ~63 MB to the footprint ledger jetsam reads (32.7 MB of it
> itemised as `ledger_tag_graphics_footprint`, the rest unitemised by `TASK_VM_INFO` and
> unattributed by `vmmap`), while the iOS build maps ~11 MB file-backed into `external` and
> charges the ledger ~5 MB. Extensions are capped around 48-50 MB, so which behaviour a
> device has decides whether Vision fits, and there is no device measurement.
> `.accurate` is separately unusable in a long-lived process: its cost grows with the number
> of *distinct* images seen and does not plateau (macOS 198 MB over 30 images, 207 over 60,
> 124 over one image thirty times), so any figure for it is a lower bound and not a ceiling.
> `Bar/screen-context/harness/run-memory.sh` re-takes all of it and asserts the
> compute-device control.

A second gotcha, because §5.5 cost a design revision to learn:

> **A frame fingerprint is only as good as the band it is taken over, and the obvious band
> is wrong.** `Bar/screen-context/harness/frame-hash.mjs` renders each corpus scene with
> only its newest message's glyphs changed and asks whether the fingerprint notices.
> Cropping the bottom 45% "where our keyboard sits" removes the newest message from the
> fingerprint: 23 of 29 pairs then hash identically, and widening the hash from 64 to 256
> bits fixes none of them. Cropping `VisionScreenReader.Band` instead — top 14% for the
> status and navigation bars, bottom 8.5% for the composer — gives 0 of 29 misses and, just
> as importantly, 0 of 30 false invalidations from the clock ticking or the header changing
> to "typing...". Over the right band a 64-bit difference hash still collides on 10 of 29;
> the shipped identity is a SHA-256 of the 32x64 greyscale reduction, and the perceptual
> hash is kept only for settle detection. **And our own keyboard is not part of the screen
> either**: with the result panel loading over the same band, our shimmer alone moves the
> identity on 30 of 30 frames, so the keyboard publishes the fraction of the screen it
> covers and the producer crops it out (§5.5.1).

---

## 10. Open risks

Ordered by how much of the design they can invalidate.

| # | Risk | What would resolve it |
|---|---|---|
| **R0** | **App Review.** A ReplayKit broadcast upload extension used to OCR the user's screen for a keyboard is not what the API is for. Rejection under 2.5.1 (private/undocumented use of an API) or 5.1.2 (data use) is a live possibility, and no amount of engineering answers it. This is the risk most likely to kill the feature and it is not technical. Deleting the speculative upload (§5.1) helps the 5.1.2 half and does nothing for the 2.5.1 half. | A pre-review question to App Review describing the flow, or a TestFlight external build. Ask before Phase 3, not after Phase 8. |
| **R3** | **Which memory-accounting behaviour a device has.** macOS charges a cpu-only Vision request ~63 MB of `phys_footprint`; the iOS Simulator charges ~5 MB and maps ~11 MB file-backed. Same model file, same compute device. This is now the *only* thing standing between the on-device path being closed and being open, and it is unmeasured. Promoted from the bottom of this table because the ANE explanation that used to answer it is withdrawn. | `memory.swift` built for `arm64-apple-ios`, run as a device unit test, all 30 images, two runs, ledger breakdown recorded. Under ~30 MB for `.fast` + rectangles reopens §5.6; near the macOS figure confirms the default. |
| **R2** | Is the broadcast ceiling really ~50 MB on iOS 26? It is in no header on this machine. §2.4 has 6-11 MB of headroom against it, so a 40 MB reality kills the design. | Device build that allocates in 1 MB steps and logs `phys_footprint` until it dies. The last logged value is the answer. |
| **R2b** | Is the keyboard ceiling really ~48 MB? Reported by review, not re-derived here. | Same experiment, in the keyboard extension. |
| **R1** | Pixel format, resolution and rate ReplayKit actually delivers. 7.6 MiB of the budget swings on 420f versus BGRA. | Log `CVPixelBufferGetPixelFormatType`, width, height and inter-frame interval from `processSampleBuffer` on device for 60 s. |
| **R2c** | The broadcast extension's own baseline, guessed at 20 MB, is the largest unmeasured line in §2.4. | Phase 3: the shutter with no reading in it, on a device, memory graph attached. |
| **R14** | **`isSecureTextEntry` is `@optional` and therefore `Bool?`.** Verified in the header (`UITextInputTraits.h:239` opens the optional block, the property is at `:257`) and by the compiler. §3.3.1 specifies the guard to fail closed on `nil`, which is correct and may also mean it refuses every read on every host. Whether hosts populate the trait through the proxy is unknown, and if they never do, the guard as written disables the feature rather than protecting it. | Ship both counters (`refusedSecure`, `refusedSecureUnknown`) in Phase 7 and read them off the first device run. If the unknown counter equals the tap count, find a different signal — do not flip the default. |
| R15 | **The fingerprint's residual blind spot.** §6.2: when the newest message is drawn under the host keyboard, two conversations can be pixel-identical in the visible band, and condition 4 cannot separate them. Measured on `sl-05`, one of 30 corpus frames. Bounded by condition 5's 20 s cap and by the fact that unreadable content is also unread content, but not closed. | Nothing on the fingerprint side closes it. If it shows up in practice, the answer is `VisionScreenReader`'s: refuse rather than answer. |
| R7 | `URLSession` + TLS footprint inside a broadcast upload extension, guessed at 4-8 MB. Network *working* is almost certain — uploading is the extension point's purpose — but the memory it costs is not. | Request from `broadcastStarted` on device, with `MemoryGovernor` sampled before and during. |
| ~~R5~~ | ~~Does 603x1311 hurt the cloud reader? Bar scores were taken at 1206x2622.~~ **Closed 2026-08-08, §2.2.1.** It does not. The downscale stays. | Done: cloud harness as a 2x2 over size and encoder, two runs a cell, one sitting. |
| R6 | Does `broadcastAnnotatedWithApplicationInfo` fire on every app switch or only the first? The header says the first. If it fired on every switch, §5.1 would have to be re-argued — that is how load-bearing it is. | Device log across three app switches inside one broadcast. |
| R8 | Can a keyboard extension host a working `RPSystemBroadcastPickerView`? Decides whether restart is in-place or requires leaving the app. | Device build; tap it. |
| R9 | Can a keyboard extension call `extensionContext.open(_:)`? Header allows it, folklore says no. | Device build; log the `success` flag. |
| R10 | Does two processes mmap'ing one file in an App Group container actually give coherent shared memory on iOS? Standard POSIX says yes; iOS sandboxing has surprised people before. | Check 5 in `prove-app-group.sh`. Cheap, and Phase 2 blocks on it. |
| R11 | Does the broadcast survive a screen lock? `RPRecordingErrorSystemDormancy` suggests the power button ends it. If a lock ends every session, the feature's session length is measured in minutes and onboarding has to say so. | Lock the device mid-broadcast; observe whether `broadcastFinished()` fires. |
| R12 | The 20 s staleness backstop is a guess. Less load-bearing now that §6 condition 3 exists, but still a guess. | Instrument settle-to-tap interval; set the cap at p95. |
| R13 | Does protected content actually black out under ReplayKit? The README already claims it. §5.1 deliberately does not rely on it. | Capture a banking app and a DRM video on device. |
| R16 | §5.5 is measured on rendered corpus frames, not on real app pixels. The band fractions come from `VisionScreenReader.Band`, which was measured off those same frames. A real WhatsApp on a real phone with our keyboard up compresses the thread differently, and the newest message may sit closer to the composer than it does here. | Capture ten real frames on device with the keyboard up, run the same reduction, and check the newest message still lands inside the 14%-91.5% band. Phase 3 has the device time to do it. |

---

## How the numbers were taken

**§1.1's accuracy table.** `AIKeyboardCoreTests/ScreenContextBarTests.swift`, run on the
iOS Simulator, which is the only place the on-device half runs the way a phone runs it.
One `ScreenContextSession` for all thirty frames, only the network replaced by a transport
replaying recorded answers. The cloud-only column is `Bar/screen-context/cloud_outputs.json`
scored by the same scorer.

**§2.3.** `Bar/screen-context/harness/memory.swift`, driven by `run-memory.sh`, both in
this repo. The probe reads `phys_footprint`, the ledger tags and `internal`/`external` out
of `task_info(mach_task_self_, TASK_VM_INFO, ...)` after each of the 30 images in
`Bar/screen-context/images/`, one image alive at a time, one reused request per process. It
reports its own deployment and, before anything runs, `supportedComputeStageDevices` for
every request it will use. It exits non-zero rather than printing a number it could not
take.

```
Bar/screen-context/harness/run-memory.sh                        # both deployments
SCALES="1.0 0.5 0.25" Bar/screen-context/harness/run-memory.sh   # the resolution sweep
PASSES=2 ./memory-host ../images accurate 1.0                    # the §2.3.2 climb
SAME_IMAGE=1 ./memory-host ../images accurate 1.0                # one distinct image
```

Taken 2026-08-08 on macOS 26.5.1 (25F80) and on the iOS 26.2 arm64 simulator runtime
(iPhone 17 Pro), Xcode 26.2 (17C52). **Neither is a device.** The script asserts that
`VNDetectTextRectanglesRequest` reports `[cpu]` on both deployments and fails if that ever
stops being true, because that is the control the §2.3.1 argument rests on. The
`vmmap -summary` figures in §2.3.1 were taken against the same binary held at its first
detector call.

The previous revision's control was the presence of `AppleNeuralEngine.framework`. That
assertion was true and explained nothing, and asserting a true irrelevance is how the
inverted argument in §1 survived a revision. It has been replaced, not merely relaxed.

**§5.5 and §6.** `Bar/screen-context/harness/frame-hash.mjs`, Playwright/Chromium on the
macOS host at 1206x2622, over the same 30 scenes `generate.mjs` renders the corpus from.
210 frames in total: each scene as-is, with every message's glyphs substituted, with only
the newest message's glyphs substituted, with only the status-bar clock and the header
presence line changed, and three renders with our own keyboard up and the result panel
loading. Substitution is a letter-for-letter shift inside the same script, so
character counts, word breaks, digits, times and bubble geometry are byte-for-byte
preserved and only the glyphs move; anything weaker also moves the line wrapping, and then
a fingerprint separates the pair for the wrong reason.

```
node Bar/screen-context/harness/frame-hash.mjs
KEEP=1 node Bar/screen-context/harness/frame-hash.mjs   # keep the 210 rendered frames
```

**The JPEG size table (§2.2).** Pillow 11.3.0 on macOS over all 30 images at quality 70,
LANCZOS resample. CoreGraphics will not produce byte-identical results; the ratios are what
the design depends on.

**§3.3.1's Swift types.** Compiled against `iPhoneSimulator26.2.sdk` with a deliberate type
error, so the compiler names the type rather than the document guessing at it.

**Everything else in §2.2 and §2.4** is arithmetic or an estimate, and each row says which.
