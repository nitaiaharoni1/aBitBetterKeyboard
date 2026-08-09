# The bar: a real device, 2026-08-09

The first install of this keyboard on a real iPhone (TestFlight build 1,
iOS 26, Full Access granted, keyboard added). Everything below is what the
owner of the phone observed, in their words, followed by what the stock iOS
keyboard and Gboard do in the same moment. **The stock keyboard is the bar.**
A piece is done when a fresh critic, holding this file and the code, cannot
name a way the product still falls short of the third column.

| # | Reported | Stock iOS keyboard / Gboard |
|---|---|---|
| D1 | "the keyboard typing is not working, its not sending the typed chars to the input" | A tap puts a character in the field. Always. |
| D2 | "and not the auto complete" | Three candidates above the keys, the middle one committed by space. |
| D3 | "it doesnt have capeability to change language within it, we need a swipe on space to make it switch lang (also ui indication somehow)" | Globe switches; on Gboard a swipe along the space bar switches, and the space bar names the language it just moved to. |
| D4 | "also i gave it full access but still it asked for it" | Nothing asks twice for permission already granted. |
| D5 | "also the read screen via broadcast doesnt work" | (No stock equivalent. The bar is: it works, or it says exactly why in words the phone's owner can act on.) |
| D6 | "we should have a quick fix/rewrite in our top of the keyboard, that is logic is by our default tone. best if default tone can also be custom and describes as a short prompt" | Gboard puts its one-tap actions in the suggestion row. Reachable without opening a panel. |
| D7 | "the playground says type a sentence but there is already a sentence types, so change the instruction to guide it to fix text or something (typing is obvious)" | Instructions describe the next useful action, never one already done. |
| D8 | "we should have a quick button to share screen context in the keyboard" | (No stock equivalent. The bar is: reachable from the keyboard, or an honest statement of why iOS forbids it.) |
| D9 | "when sharing context do not show frames, because it alarms, the user too much" | A capture indicator says *that* it is recording, never *what* it saw. |
| D10 | "we need to support all languages" | The stock keyboard ships ~80 layouts and the user picks. |

## What "typing works" means precisely

Not "the controller mutates a mock". The extension's own wiring has to hold:
the object that talks to `UITextDocumentProxy` must outlive `viewDidLoad`, and
the proxy must be re-resolved when the host changes the focused field. Any test
that keeps its target in a method-scoped local proves nothing — the local
outlives the assertion. Take the reference out of scope, then assert.

## Standing constraints (these are not negotiable, and a fix that breaks one is not a fix)

- A keyboard extension has **no** `UIApplication`, so no `openURL`, no
  `openSettingsURLString`, no launching the container app. The responder-chain
  `openURL` trick is explicitly disallowed by Apple.
- A keyboard extension has **no microphone**, with or without Full Access.
- Without Full Access the keyboard has **no App Group and no network**. So
  anything the app learns about the keyboard through the shared container is
  learned only when Full Access is already on.
- `AIKeyboardBroadcast` must never link `AIKeyboardCore` (50 MB jetsam cap).
  `Scripts/prove-capture-channel.sh` check 1 reads the Mach-O and enforces this.
- On-device Foundation Models has **no Hebrew**. `UITextChecker` **does**
  (`he_IL` among 42 languages). Do not reason from one to the other.
- The keyboard UI lives in `Packages/AIKeyboardCore/`, never in
  `AIKeyboardExtension/`, or it stops working in the app's playground.
- Trunk only. No feature branches, no worktrees.
- The suite stays green: `xcodebuild test -project AIKeyboard.xcodeproj -scheme AIKeyboard -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
