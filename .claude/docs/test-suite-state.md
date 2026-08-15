# What the test suite actually reports

NIT-92 exists because nobody knew. This file is the answer, with a date and a
commit on it, so the next person can tell a new failure from one that was
already there. **Re-run it and update this table rather than trusting it**: every
number here is a reading, not a property of the code.

## The run

| | |
|---|---|
| Date | 2026-08-16 |
| Commit | `98946cf4` plus the working tree described below |
| Destination | iPhone 17 Pro, iOS 26.2 simulator, uncontended |
| Command | `xcodebuild test -project AIKeyboard.xcodeproj -scheme AIKeyboard -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:AIKeyboardCoreTests` |

**`AIKeyboardCoreTests`: 1271 executed, 1260 passed, 8 failed, 3 skipped.**

All eight are the emoji failures described below, and all eight are older than
any current work. The 3 skipped are what the earlier run's "1257 declared, 1252
executed" gap actually was; `xcodebuild` reports them, so read the skip count
rather than subtracting.

`xcodebuild build` does **not** compile these targets, so a compile check needs
`build-for-testing`.

**The UI bundle is excluded from that command and from the numbers above**, on
purpose. See "The UI tests" at the bottom: it is unproven rather than passing or
failing, and folding it in would turn one honest number into a misleading one.

### The previous reading, for comparison

2026-08-15 on `fd2a480c`: 1274 executed across both bundles, 1238 passed, 36
failed, of which 17 were core. Core went 17 failures to 8 by fixing nine of
them, and gained 19 tests (the landscape geometry).

## How the failures were separated from our own changes

A pristine `git archive HEAD` was exported to a temp directory (not a worktree)
and the suspect classes were run there against the same simulator. That is the
only way to answer "was this already red", and it is worth the ten minutes: it
moved twelve failures out of the "we broke it" column and found two bugs nobody
was looking for.

## Pre-existing failures, confirmed identical on committed `main`

Twelve were found. **Four of them turned out to be stale assertions rather than
product questions, and calling all twelve "product questions" was wrong.** They
are listed under "Fixed" below. What is left is eight, and these eight really are
decisions somebody has to make.

| Test | What it reports |
|---|---|
| `EmojiSearchTypingTests` (5 tests) | The emoji search box inherits the document's shift. See the section below, which names the exact line. |
| `EmojiModeTests` (3 tests) | Search ranking. `לב` returns 💏 rather than ❤️, and `car` puts 🚗 at index 5 behind 🚕 and 🚙. |

**The `לב` one is not a data gap, and a data fix was tried and reverted.**
Giving 🫀 a distinct Hebrew name (`לב אנטומי` rather than the bare `לב` it shares
with the query) moves 🫀 out of the way and then **💏 wins instead**, and it
breaks `testRecentsWinACloseCallAndLoseToAName`, which deliberately relies on
🫀's Hebrew name being exactly `לב`. So the ranker, not the catalogue, is what
puts a kiss above a red heart for the word "heart". Do not repeat that fix.

`car` is the same shape: 🚗, 🚕 and 🚙 all carry `car` as an exact keyword, and
🚗's own CLDR name is `automobile`, not `car`, so no name-match tiebreak favours
it either. Both want a ranking decision, and there is no measured harness for
emoji search the way there is for typing, so a ranker change cannot currently be
scored.

### The emoji search shift question, with the line

All five `EmojiSearchTypingTests` failures reduce to one fact.
`KeyboardController+Typing.consumeForEmojiSearch` already does the right thing:

```swift
setEmojiQuery(emojiQuery + (shift.isUppercase ? language.uppercased(value) : value))
if shift == .on { shift = .off }
```

Shift applies to the query as a one-shot, which is a deliberate design and is
what `testShiftDoesNotBreakTheSearch` expects. The bug is only that shift is
**inherited from the document** when the box opens: an empty field arms shift at
focus, so `cat` is typed as `Cat`, and a shift press from that inherited `.on`
gives `.locked` where the test expects `.on`.

**The fix is save-and-restore around the search session, and it is not a
one-liner, which is why it was left.** Setting `shift = .off` on entry without
restoring it would leave shift off after the box closes, losing the capital at a
sentence start, which is worse than the cosmetic problem it fixes. A correct fix
has to catch **four** exit paths that write `overlay` directly:
`show(_:)`, `dismissOverlay()`, `KeyboardController+AI.swift:213`, and
`KeyboardController+Dictation.swift:416`. Miss one and shift is stuck `.off` in
the core typing path.

## Fixed in this pass

| Test | Why it failed |
|---|---|
| `AutocapitalizationTests` (2 tests) | `target.autocapitalizationType = .none` assigns **`Optional.none`, which is nil**, not `UITextAutocapitalizationType.none`. The tests were setting "the host declared nothing", correctly getting `.sentences`, and reporting a bug in code that was right. Spelled out as `UITextAutocapitalizationType.none`. |
| `FieldKeyboardTypeTests.testAnEmailFieldDoesNotArriveWithShiftArmed` | The same assignment, the same way. |
| `FieldKeyboardTypeTests.testEveryLatinWantingFieldTypeMovesOffHebrew` | It asserted `.webSearch` moves off Hebrew while `testASearchFieldLeavesAHebrewKeyboardAlone`, two screens down, asserted it stays. One of the pair had to be red whatever the code did. `latinFieldTypes` deliberately excludes `.webSearch`, so the list was wrong and `.webSearch` came out of it. |
| `CustomKeyActionTests.testTheQuickToneKeySaysWhyWithNothingToRewrite` | `XCTAssertEqual(controller.block?.remedy, .none)` compares against nil, but the block correctly carries `Remedy.none`. Its own message ("there is no button that would help") describes the enum case it failed to assert. |
| `SparkleReachabilityTests.testReplyDoesNotOpenTheAppWhenThePromptWithholdsTheStart` | The same trap twice more, at `AIButtonTests.swift:211` and `:221`. `refuseForScreenContext` builds its block as `remedy: prompt.offersPicker ? .broadcastPicker : .none`, and `offersPicker` is asserted false one line above, so `Remedy.none` is exactly what was meant. **This was first filed as a product question and it was not one.** |
| `LanguageReachabilityTests.testAnAlternateIsNeverTheKeyItSitsOn` | The blanket rule "no alternate is ever the key it sits on" has one deliberate exception the test did not carry. `.claude/rules/keyboard-layout.md` records that the period popup is SwiftKey's order `! @ # , . ?` **including the period**, aligned so it sits over the key it came from, with `alternateRestIndex` naming the period so lifting without sliding still types a full stop. Removing it would move every other mark. The key is exempted by `punctuationKeyID`; every other key still has to obey. |
| `SpaceBarGestureOrderTests.testADeleteRollingOverAnOpenSpaceTouchLandsAfterTheSpace` | It asserted the corrected word, which is what a delete that removed only the trailing space would leave. The space commits the swap and arms `pendingAutocorrectUndo`, so the delete landing after it is the delete that **takes the swap back**, exactly as `insertSpace` documents. The answer is the original word, and that is the ordering working. The assertion predates the undo. |
| `EmojiModeTests.testEveryEmojiHasAHebrewNameAndAnEnglishOne` | A real one-entry data gap, not a test bug. 📀 was `"dvd"` with no Hebrew half while all 1869 of its neighbours are `english\|hebrew`. Now `"dvd\|דיסק DVD"`. Every entry in the catalogue was rescanned; this was the only one, in either direction. |

## `.none` in an optional position is the trap this repo keeps falling into

Four of the fixes above are the same mistake, across three files, and `AGENTS.md`
already records a fifth: `FrameIdentity` is spelled `.absent` precisely because
`FrameIdentity.none` in an optional position silently resolves to
`Optional.none`. When the type of the expression is `T?` and `T` has a case
called `none`, Swift picks `Optional.none` and says nothing.

**Write the type out.** `UITextAutocapitalizationType.none`, not `.none`. It is
four extra words and it is the difference between a test that measures the code
and a test that measures Swift's overload resolution.

## The UI tests

19 of 22 failed. They are excluded from the "green" claim above and they are
**not** evidence of a regression: they drive the real Settings app to enable the
keyboard and grant Full Access, and most fail with the app's TabBar never
appearing after that excursion. `AGENTS.md` already warns that these need an
uncontended simulator; what this run shows is that an uncontended simulator is
necessary and not sufficient. Treat the UI bundle as unproven rather than as
passing or failing until somebody sits with it.

**One UI-adjacent finding is real and was fixed by accident.**
`CustomKeyActionTests.testCopyclipKeyTogglesThePanel` **hangs indefinitely** on
committed `main`: toggling the CopyClip panel reads `UIPasteboard.general.string`,
which blocks the main thread until the "Allow Paste?" alert is answered, and
nothing answers it under `xcodebuild test`. That is NIT-23's defect, stated in
its own words, reproducing as a hung test rather than a failing one. The
`UIPasteControl` work removed that read, so the test now runs and passes. A
hanging test is worse than a failing one, because it looks like a slow suite.
