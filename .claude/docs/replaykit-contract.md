# ReplayKit broadcast contract

Bar material. Every claim here was read out of the SDK on this machine on
2026-08-08, not recalled:

```
$(xcrun --sdk iphoneos --show-sdk-path)/System/Library/Frameworks/ReplayKit.framework/Headers/
```

A critic judging capture code should check it against this file, and check this
file against those headers if anything looks wrong.

## What runs where

A keyboard extension cannot capture the screen. A **broadcast upload extension**
can, system-wide, including while the user is in WhatsApp. That is the only
route on this deployment target: ScreenCaptureKit is iOS 27+ and absent from the
installed iOS 26.2 SDK.

`RPBroadcastSampleHandler` is the class to subclass. Selecting it is an
Info.plist decision, not a code one:

| Key | Value |
|---|---|
| `NSExtensionPointIdentifier` | `com.apple.broadcast-services-upload` |
| `NSExtensionPrincipalClass` | the `RPBroadcastSampleHandler` subclass |
| `RPBroadcastProcessMode` | `RPBroadcastProcessModeSampleBuffer` |

The header is explicit that the mode key is what enables sample-buffer handling:
*"To enable this mode of handling, set the RPBroadcastProcessMode in the
extension's info.plist to RPBroadcastProcessModeSampleBuffer."* Without it the
handler is never called, and that failure looks like a broadcast that starts and
delivers nothing.

## Lifecycle

```objc
- (void)broadcastStartedWithSetupInfo:(nullable NSDictionary *)setupInfo;
- (void)broadcastPaused;
- (void)broadcastResumed;
- (void)broadcastFinished;
- (void)broadcastAnnotatedWithApplicationInfo:(NSDictionary *)applicationInfo;  // iOS 11.2+
- (void)processSampleBuffer:(CMSampleBufferRef)sampleBuffer withType:(RPSampleBufferType)type;
- (void)finishBroadcastWithError:(NSError *)error;
```

`RPSampleBufferType` is `Video = 1`, `AudioApp`, `AudioMic`. Screen reading wants
video only; the audio cases must be ignored rather than fallen through, because
they arrive far more often than video frames.

Orientation rides as an attachment, not a property:
`CMGetAttachment(sampleBuffer, RPVideoSampleOrientationKey, …)`, valued as
`CGImagePropertyOrientation`. Code that ignores it reads a landscape frame
sideways.

## Which app is being read

`broadcastAnnotatedWithApplicationInfo:` delivers a dictionary keyed by
`RPApplicationInfoBundleIdentifierKey` (iOS 11.2+).

**Read the header's wording carefully before designing around it.** It is called
*"when broadcast is started from Control Center and provides extension
information about the first application opened or used during the broadcast."*

Two consequences, and both are load-bearing for a "reading WhatsApp" strip:

1. It reports the **first** app, not the current one. A user who starts in
   WhatsApp and switches to Telegram is not announced again.
2. It is tied to the Control Center start path.

So the app name shown to the user cannot be assumed live. Either it is derived
some other way, or the UI must not claim to know which app is on screen. A
design that prints a stale app name next to a fresh message is worse than one
that prints no app name at all.

`NSExtensionContext.loadBroadcastingApplicationInfoWithCompletion:` also exists
on iOS and yields bundleID, display name and icon, but it lives on the extension
*context*, which is the setup UI extension's world, not the upload extension's
steady state.

## The memory ceiling

A broadcast upload extension is killed for exceeding **50 MB**. Not a guideline:
a hard cap enforced by jetsam, and the extension dies rather than degrades. This
is the constraint that decides the whole architecture, so treat any design that
does not do the arithmetic as unjudged.

For scale, one frame at the bar's own resolution: 1206 × 2622 × 4 bytes ≈
**12.6 MB** for a single BGRA buffer. Three of those in flight is the whole
budget. Anything holding a `CVPixelBuffer` past the return of
`processSampleBuffer:withType:` is a bug, and anything allocating a second
full-size copy needs to justify itself against that number.

**iPad is not the same problem as iPhone.** ReplayKit delivers much larger
frames there, and a pipeline comfortably under the cap on an iPhone goes over it
on an iPad Pro. This project does not build iPad layouts yet, but a capture
design that only works because iPhone frames happen to be small should say so
rather than discover it later. The standard mitigation is to downsample early,
before anything else touches the buffer.

Sources, all Apple Developer Forums threads describing the cap and the deaths it
causes: [broadcast upload extension crash](https://developer.apple.com/forums/thread/131210),
[extension limit vs large frames on iPad](https://developer.apple.com/forums/thread/651367),
[replayd killed by jetsam, reason highwater](https://developer.apple.com/forums/thread/706972).

## Where it can be verified

**Not in the simulator.** Measured 2026-08-08: the iOS 26.2 simulator runtime
ships no `replayd` and no broadcast launch daemons, while the macOS host has
`/usr/libexec/replayd`, which is the control that makes the absence meaningful.
`ReplayKit.framework` *is* in the simulator SDK, so this code compiles and links
and a picker can even be presented. No session ever starts.

That gap is the trap: a simulator run can look like success. Any claim that
capture works must come from a physical device, proved the way
`Scripts/prove-app-group.sh` proves things — a verdict read from a log line
stamped by the other process, and a script that fails rather than skips when it
cannot check.
