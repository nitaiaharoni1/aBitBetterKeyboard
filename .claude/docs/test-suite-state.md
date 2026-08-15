# What the test suite actually reports

NIT-92 exists because nobody knew. This file is the answer, with a date and a
commit on it, so the next person can tell a new failure from one that was
already there. **Re-run it and update this table rather than trusting it**: every
number here is a reading, not a property of the code.

## The run

| | |
|---|---|
| Date | 2026-08-15 |
| Commit | `fd2a480c` plus the working tree described below |
| Destination | iPhone 17 Pro, iOS 26.2 simulator, uncontended |
| Command | `xcodebuild test -project AIKeyboard.xcodeproj -scheme AIKeyboard -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` |

**1274 tests executed. 1238 passed, 36 failed.** 1252 of those are
`AIKeyboardCoreTests` and 22 are `AIKeyboardUITests`.

Write the count down, because a silently skipped bundle is invisible otherwise.
`AIKeyboardCoreTests` declares **1257 `func test…` methods across 105 files** and
**1252 of them executed**, so five are declared and not run. That gap is small
enough to look like nothing and is exactly what this line exists to make
visible: check it before assuming a bundle ran. `xcodebuild build` does **not**
compile these targets, so a compile check needs `build-for-testing`.

## How the failures were separated from our own changes

A pristine `git archive HEAD` was exported to a temp directory (not a worktree)
and the suspect classes were run there against the same simulator. That is the
only way to answer "was this already red", and it is worth the ten minutes: it
moved twelve failures out of the "we broke it" column and found two bugs nobody
was looking for.

## Pre-existing failures, confirmed identical on committed `main`

These twelve fail the same way with none of the current work applied. They are
**not** regressions, and they are not fixed here.

| Test | What it reports |
|---|---|
| `EmojiSearchTypingTests` (5 tests) | The emoji search box capitalises the query. `shift` starts `.on` and nothing lowers it before the query is built, so `cat` is typed as `Cat`, and `testTheKeysThatChangeWhichLettersAreOnScreenStillWork` finds `.locked` where it expects `.on`. |
| `EmojiModeTests` (4 tests) | Search ranking and the Hebrew name table. `לב` returns 🫀 rather than ❤️, an exact keyword does not outrank a prefix match, and 📀 has no Hebrew name. |
| `LanguageReachabilityTests.testAnAlternateIsNeverTheKeyItSitsOn` | Both English and Hebrew offer `.` as its own alternate. |
| `SpaceBarGestureOrderTests.testADeleteRollingOverAnOpenSpaceTouchLandsAfterTheSpace` | Ordering of a delete that rolls over an open space touch. |
| `SparkleReachabilityTests.testReplyDoesNotOpenTheAppWhenThePromptWithholdsTheStart` | Reply opens the app when the prompt withholds the start. |

Each is a real product question rather than a stale assertion, which is why none
of them is edited here. They want their own issue and their own decision.

## Fixed in this pass

| Test | Why it failed |
|---|---|
| `AutocapitalizationTests` (2 tests) | `target.autocapitalizationType = .none` assigns **`Optional.none`, which is nil**, not `UITextAutocapitalizationType.none`. The tests were setting "the host declared nothing", correctly getting `.sentences`, and reporting a bug in code that was right. Spelled out as `UITextAutocapitalizationType.none`. |
| `FieldKeyboardTypeTests.testAnEmailFieldDoesNotArriveWithShiftArmed` | The same assignment, the same way. |
| `FieldKeyboardTypeTests.testEveryLatinWantingFieldTypeMovesOffHebrew` | It asserted `.webSearch` moves off Hebrew while `testASearchFieldLeavesAHebrewKeyboardAlone`, two screens down, asserted it stays. One of the pair had to be red whatever the code did. `latinFieldTypes` deliberately excludes `.webSearch`, so the list was wrong and `.webSearch` came out of it. |
| `CustomKeyActionTests.testTheQuickToneKeySaysWhyWithNothingToRewrite` | `XCTAssertEqual(controller.block?.remedy, .none)` compares against nil, but the block correctly carries `Remedy.none`. Its own message ("there is no button that would help") describes the enum case it failed to assert. |

## `.none` in an optional position is the trap this repo keeps falling into

Three of the five fixes above are the same mistake, and `AGENTS.md` already
records a fourth: `FrameIdentity` is spelled `.absent` precisely because
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
