import XCTest

@testable import AIKeyboardCore
@testable import AIKeyboardShared

/// The evidence the containing app has that its keyboard exists.
///
/// Every test here writes into a scratch directory rather than the App Group,
/// because this target carries no App Group entitlement — `SharedContainer.url`
/// is nil in it, which is exactly the state the real keyboard is in before the
/// user grants Full Access. That is why `record(hasFullAccess:at:)` and
/// `load(from:)` take a URL.
final class KeyboardPresenceTests: XCTestCase {

    private var directory: URL!
    private var url: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("presence-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent(KeyboardPresence.fileName)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    // MARK: Absence

    /// A file that is not a record must not decode into one.
    ///
    /// The wrong implementation this rejects is a lenient decode — a hand-rolled
    /// one, or a `Codable` conformance that defaults the fields it cannot find.
    /// `{"hasFullAccess": true}` with no timestamp would come back as a
    /// confirmation stamped zero, and zero is the one value `CaptureClock.elapsed`
    /// treats as infinitely old, so it would tick Full Access and then never
    /// expire. Both halves are asserted, because the decode returning nil is only
    /// half the reason it is safe.
    func testAFileThatIsNotARecordIsNotAConfirmation() throws {
        try Data(#"{"hasFullAccess":true}"#.utf8).write(to: url)
        XCTAssertNil(KeyboardPresence.load(from: url))

        let stampless = SetupState(
            presence: KeyboardPresence(hasFullAccess: true, recordedAt: 0, bootIdentity: 7),
            now: 5_000, bootIdentity: 7)
        XCTAssertEqual(stampless.fullAccess, .unknown)
        XCTAssertEqual(stampless.keyboardAdded, .unknown)
    }

    /// A record written by the build before `bootIdentity` existed has to fail the
    /// decode rather than migrate to a default, because a default would be either
    /// zero — which never matches — or this boot, which would be a fabricated claim
    /// that the previous build's record was written since the last restart.
    func testARecordWithoutABootIdentityDoesNotDecode() throws {
        try Data(#"{"hasFullAccess":true,"recordedAt":1000}"#.utf8).write(to: url)
        XCTAssertNil(KeyboardPresence.load(from: url))
    }

    /// The one thing `bootIdentity` is read from, checked against itself: a value
    /// that changed between two reads inside one test run would make every
    /// confirmation expire immediately, and a zero would make every confirmation
    /// impossible. Neither is a hypothetical — both are what this device would do
    /// if `kern.boottime` were unreadable in an app extension's sandbox.
    func testTheBootIdentityIsReadableAndStable() {
        let first = KeyboardPresence.bootIdentity
        XCTAssertNotEqual(first, 0, "kern.boottime could not be read")
        XCTAssertEqual(first, KeyboardPresence.bootIdentity)
    }

    /// A container the process cannot write to is the keyboard without Full
    /// Access, and it must report failure rather than leaving the caller
    /// believing a record exists.
    func testAnUnwritableContainerRecordsNothing() {
        let unreachable =
            directory
            .appendingPathComponent("no-such-directory", isDirectory: true)
            .appendingPathComponent(KeyboardPresence.fileName)

        XCTAssertFalse(KeyboardPresence.record(hasFullAccess: true, at: unreachable))
        XCTAssertNil(KeyboardPresence.load(from: unreachable))
    }

    // MARK: Presence

    func testRecordingLeavesAReadableRecord() {
        XCTAssertTrue(
            KeyboardPresence.record(hasFullAccess: true, at: url, now: 5_000, bootIdentity: 11))

        let record = KeyboardPresence.load(from: url)
        XCTAssertEqual(record?.hasFullAccess, true)
        XCTAssertEqual(record?.recordedAt, 5_000)
        XCTAssertEqual(record?.bootIdentity, 11)
    }

    // MARK: Cost

    /// The write sits on the keyboard's own launch path, so a record that is
    /// already current must not be rewritten. `record` still reports true: the
    /// question it answers is "does the container hold a record for this run",
    /// not "did I just write one".
    func testACurrentRecordIsNotRewritten() {
        let written = CaptureClock.nanoseconds(10)
        XCTAssertTrue(KeyboardPresence.record(hasFullAccess: true, at: url, now: written))

        let later = written + KeyboardPresence.refreshInterval
        XCTAssertTrue(KeyboardPresence.record(hasFullAccess: true, at: url, now: later))
        XCTAssertEqual(
            KeyboardPresence.load(from: url)?.recordedAt, written,
            "a record inside the refresh interval was rewritten")
    }

    func testAStaleRecordIsRewritten() {
        let written = CaptureClock.nanoseconds(10)
        KeyboardPresence.record(hasFullAccess: true, at: url, now: written)

        let later = written + KeyboardPresence.refreshInterval + 1
        KeyboardPresence.record(hasFullAccess: true, at: url, now: later)
        XCTAssertEqual(KeyboardPresence.load(from: url)?.recordedAt, later)
    }

    // MARK: Self-healing

    /// A run that read `hasFullAccess` as false must not pin the answer until the
    /// refresh interval runs out: a disagreeing flag rewrites the record however
    /// recent it is. This is the whole reason the app may believe a `false` — one
    /// bad reading costs the user one more switch to the keyboard, not six hours
    /// of being told a permission they granted is missing.
    func testADisagreeingFlagRewritesImmediately() {
        let now = CaptureClock.nanoseconds(10)
        KeyboardPresence.record(hasFullAccess: false, at: url, now: now)
        XCTAssertEqual(KeyboardPresence.load(from: url)?.hasFullAccess, false)

        KeyboardPresence.record(hasFullAccess: true, at: url, now: now)
        XCTAssertEqual(
            KeyboardPresence.load(from: url)?.hasFullAccess, true,
            "a flag that disagrees with the stored one has to win, whatever the timestamp says")
    }

    // MARK: The clock

    /// A stamp in the future — a corrupt record, since the boot identity is what
    /// covers restarts now — has to read as "write it again" rather than as
    /// "written zero seconds ago". This is `CaptureClock.elapsed` saturating, and
    /// it is the *easy* direction; the hard one is below and in `SetupStateTests`.
    func testNeedsWritingSaturatesOnAFutureTimestamp() {
        let fromTheFuture = KeyboardPresence(
            hasFullAccess: true, recordedAt: CaptureClock.nanoseconds(9_000), bootIdentity: 3)
        XCTAssertTrue(
            KeyboardPresence.needsWriting(
                over: fromTheFuture, hasFullAccess: true, bootIdentity: 3,
                now: CaptureClock.nanoseconds(4)))
    }

    /// The direction saturation cannot see, on the writing side.
    ///
    /// A record stamped two hours into the previous boot is a *smaller* number than
    /// two hours and one minute of the current boot's uptime, so every age test
    /// passes it. Only the boot identity separates them — and it has to force the
    /// rewrite, or a keyboard in active use spends the first six hours after every
    /// restart unable to refresh the record the reader is refusing, and the card
    /// keeps saying it has never seen the keyboard while the user types on it.
    func testARecordFromAnotherBootIsRewrittenEvenWhenItsStampLooksFresh() {
        let twoHours = CaptureClock.nanoseconds(2 * 60 * 60)
        KeyboardPresence.record(hasFullAccess: true, at: url, now: twoHours, bootIdentity: 100)

        let slightlyLater = twoHours + CaptureClock.nanoseconds(60)
        // The guard the test rests on: the *age* of the record must sit inside the
        // refresh interval, or `needsWriting` would rewrite on staleness alone and
        // this would pass without the boot-identity clause it exists to pin. Sixty
        // seconds against six hours. (It used to compare `refreshInterval` against
        // three hours, which asserted the interval was shorter than it is and
        // failed outright — the age was never the thing being checked.)
        XCTAssertLessThan(
            CaptureClock.elapsed(since: twoHours, now: slightlyLater),
            KeyboardPresence.refreshInterval,
            "this test needs a stamp that is inside the refresh interval to be meaningful")
        KeyboardPresence.record(
            hasFullAccess: true, at: url, now: slightlyLater, bootIdentity: 200)

        let record = KeyboardPresence.load(from: url)
        XCTAssertEqual(record?.bootIdentity, 200, "a record from another boot was left in place")
        XCTAssertEqual(record?.recordedAt, slightlyLater)
    }

    // A test that the record survives `CaptureChannel.sweep` used to sit here and
    // has been deleted rather than kept: `sweep(container:)` removes only
    // *directories* whose name has the prefix `channel`, plus `channel/reading.json`
    // by name, so a JSON file called anything else survives from anywhere this code
    // could plausibly put it — including inside `channel/`. It asserted a property
    // no wrong implementation lacks, which is a test that cannot fail.

    // MARK: The two constants have to be in the right order

    /// The decay ceiling must be longer than the refresh interval, and this is the
    /// assertion rather than the doc comment because getting it backwards has a
    /// silent, intermittent symptom: the keyboard rewrites the record only once
    /// every `refreshInterval`, so a ceiling shorter than that would let a
    /// correctly installed keyboard fall to `.unknown` in the gap between two
    /// writes and tick again on the next use, over and over.
    func testTheConfirmationWindowOutlastsTheRefreshInterval() {
        XCTAssertGreaterThan(
            KeyboardPresence.confirmationWindow, KeyboardPresence.refreshInterval,
            "a record can be up to one refresh interval old on a phone in constant use")
    }
}

/// The reading of the record: the mapping that *is* the D4 fix.
///
/// Every case the setup card can render, with the record placed at an age of the
/// test's choosing. The wrong implementation these reject is the one that shipped:
/// three constants that answered without measuring anything.
final class SetupStateTests: XCTestCase {

    private let start = CaptureClock.nanoseconds(10_000)
    private let thisBoot: UInt64 = 4_242

    private func state(
        _ presence: KeyboardPresence?, age: UInt64 = 0,
        microphone: MicrophonePermission = .undetermined,
        cloudConfigured: Bool = false
    ) -> SetupState {
        SetupState(
            presence: presence, microphone: microphone, cloudConfigured: cloudConfigured,
            now: start + age, bootIdentity: thisBoot)
    }

    private func confirmed(_ hasFullAccess: Bool = true) -> KeyboardPresence {
        KeyboardPresence(hasFullAccess: hasFullAccess, recordedAt: start, bootIdentity: thisBoot)
    }

    // MARK: No record

    /// Nothing written means nothing known, and the card must say so rather than
    /// pick one of the three causes. The hardcoded `keyboardAdded = true` this
    /// replaced fails here, and so does a naive `presence == nil ? .blocked`.
    func testNoRecordIsThreeUnknownsAndNoTicks() {
        let setup = state(nil)
        XCTAssertEqual(setup.keyboardAdded, .unknown)
        XCTAssertEqual(setup.fullAccess, .unknown)
        XCTAssertEqual(setup.confirmedRequirements, 0)
        XCTAssertFalse(setup.isReady)
    }

    /// A keyboard that is added but has no Full Access writes nothing, so it looks
    /// from here exactly like a keyboard that was never added — and it is the most
    /// likely cause of a missing record, not the least. The words therefore have to
    /// name the permission, or the user's next move is the one they just made.
    func testTheNoRecordExplanationNamesBothCauses() throws {
        let words = try XCTUnwrap(state(nil).unresolvedExplanation)
        XCTAssertTrue(words.contains("Full Access"), "the missing permission is never named: \(words)")
        XCTAssertTrue(words.contains("added"), "adding the keyboard is never named: \(words)")
    }

    // MARK: A current record

    func testACurrentRecordTicksBoth() {
        let setup = state(confirmed())
        XCTAssertEqual(setup.keyboardAdded, .confirmed)
        XCTAssertEqual(setup.fullAccess, .confirmed)
        XCTAssertEqual(setup.confirmedRequirements, 2)
        XCTAssertTrue(setup.isReady)
        XCTAssertNil(setup.unresolvedExplanation)
    }

    /// The record exists, so the keyboard is installed; the flag says the
    /// permission is not. The app knows which case this is and must say only that.
    func testACurrentRecordReportingNoFullAccessTicksOnlyTheKeyboard() throws {
        let setup = state(confirmed(false))
        XCTAssertEqual(setup.keyboardAdded, .confirmed)
        XCTAssertEqual(setup.fullAccess, .unknown)
        XCTAssertFalse(setup.isReady)

        let words = try XCTUnwrap(setup.unresolvedExplanation)
        XCTAssertTrue(words.contains("Allow Full Access"))
        XCTAssertFalse(
            words.contains("Switch to"),
            "this user has already switched to the keyboard; telling them to do it again is the "
                + "defect this card is being fixed for")
    }

    // MARK: Decay

    /// The gap the round-1 implementation left: Full Access is revoked, the record
    /// freezes because the only process that could correct it has just lost the
    /// container, and a reader that consults only `hasFullAccess` ticks it forever.
    func testAConfirmationOlderThanTheWindowExpires() {
        let stale = state(confirmed(), age: KeyboardPresence.confirmationWindow + 1)
        XCTAssertEqual(stale.fullAccess, .unknown)
        XCTAssertEqual(stale.keyboardAdded, .unknown)
        XCTAssertEqual(stale.confirmedRequirements, 0)
    }

    /// And it expires into words that name what would have caused it, rather than
    /// into the first-run advice — the keyboard has been switched to before.
    func testAnExpiredConfirmationSaysWhatMightHaveChanged() throws {
        let words = try XCTUnwrap(
            state(confirmed(), age: KeyboardPresence.confirmationWindow + 1).unresolvedExplanation)
        XCTAssertTrue(words.contains("Allow Full Access"))
        XCTAssertTrue(words.contains("removed"))
    }

    /// The boundary, both sides, so "expires" cannot quietly become "expires a day
    /// early" or "never expires".
    func testTheWindowBoundaryIsInclusive() {
        XCTAssertEqual(
            state(confirmed(), age: KeyboardPresence.confirmationWindow).fullAccess, .confirmed)
        XCTAssertEqual(
            state(confirmed(), age: KeyboardPresence.confirmationWindow + 1).fullAccess, .unknown)
    }

    /// A phone in constant use carries a stamp up to one refresh interval old, and
    /// that must never flicker. This is the same relationship the constants assert,
    /// measured through the decision instead.
    func testARecordAtTheRefreshIntervalIsStillCurrent() {
        XCTAssertEqual(state(confirmed(), age: KeyboardPresence.refreshInterval).fullAccess, .confirmed)
    }

    // MARK: Across a restart

    /// A stamp ahead of now: the easy half, which `CaptureClock.elapsed` already
    /// handled. Kept because it pins the saturation, and named for what it is
    /// rather than for the reboot it used to claim to cover — it only ever caught
    /// reboots where the old uptime happened to be the larger number.
    func testAStampAheadOfNowExpires() {
        let fromTheFuture = KeyboardPresence(
            hasFullAccess: true, recordedAt: CaptureClock.nanoseconds(90_000),
            bootIdentity: thisBoot)
        let setup = SetupState(
            presence: fromTheFuture, now: CaptureClock.nanoseconds(4), bootIdentity: thisBoot)
        XCTAssertEqual(setup.fullAccess, .unknown)
        XCTAssertEqual(setup.keyboardAdded, .unknown)
    }

    /// The half that shipped broken, walked through in the order it happens.
    ///
    /// `recordedAt` is uptime. A record written two hours into boot A is a *smaller*
    /// number than most of boot B's uptime, so from two hours into boot B onwards
    /// every age test passes it and the card returns to "Ready to type 2/2" over a
    /// keyboard whose Full Access was revoked days earlier — and does it again after
    /// every restart, forever, because nothing ever deletes the file.
    ///
    /// The four rows below are the sequence, and only the third one used to pass.
    func testAConfirmationDoesNotComeBackAfterARestart() {
        let bootA: UInt64 = 1_000
        let bootB: UInt64 = 2_000
        let twoHours = CaptureClock.nanoseconds(2 * 60 * 60)
        let record = KeyboardPresence(
            hasFullAccess: true, recordedAt: twoHours, bootIdentity: bootA)

        func fullAccess(boot: UInt64, uptime: UInt64) -> SetupCheck {
            SetupState(presence: record, now: uptime, bootIdentity: boot).fullAccess
        }

        XCTAssertEqual(
            fullAccess(boot: bootA, uptime: twoHours + CaptureClock.nanoseconds(60 * 60)),
            .confirmed, "within the window on the boot that wrote it — the accepted trade")
        XCTAssertEqual(
            fullAccess(boot: bootA, uptime: twoHours + KeyboardPresence.confirmationWindow + 1),
            .unknown, "decay inside one boot")
        XCTAssertEqual(
            fullAccess(boot: bootB, uptime: CaptureClock.nanoseconds(10 * 60)),
            .unknown, "ten minutes into the next boot: saturation catches this one")
        XCTAssertEqual(
            fullAccess(boot: bootB, uptime: twoHours + CaptureClock.nanoseconds(60)),
            .unknown, "two hours into the next boot: the record must not come back to life")
        XCTAssertEqual(
            fullAccess(boot: bootB, uptime: CaptureClock.nanoseconds(60 * 60 * 60)),
            .unknown, "and it must not come back later in that boot either")
    }

    /// Restore from backup is the same failure with a different cause: the App Group
    /// container travels in the iCloud backup, so a phone that has never had this
    /// keyboard enabled inherits somebody else's confirmation. A boot identity from
    /// another device cannot match this one.
    func testARecordRestoredFromAnotherDeviceNeverConfirms() {
        let fromTheOldPhone = KeyboardPresence(
            hasFullAccess: true, recordedAt: start, bootIdentity: thisBoot &+ 1)
        let setup = SetupState(
            presence: fromTheOldPhone, now: start + 1, bootIdentity: thisBoot)
        XCTAssertEqual(setup.fullAccess, .unknown)
        XCTAssertEqual(setup.keyboardAdded, .unknown)
    }

    /// An unreadable `kern.boottime` reports zero, and zero must not match zero:
    /// "I do not know which boot this is" twice over is not evidence that the two
    /// are the same boot.
    func testAnUnknownBootIdentityNeverConfirms() {
        let record = KeyboardPresence(hasFullAccess: true, recordedAt: start, bootIdentity: 0)
        let setup = SetupState(presence: record, now: start + 1, bootIdentity: 0)
        XCTAssertEqual(setup.fullAccess, .unknown)
        XCTAssertEqual(setup.keyboardAdded, .unknown)
    }

    /// And the restart falls into the words about restarting, not into the first-run
    /// advice: this user has switched to the keyboard before.
    func testARestartExplainsItselfAsARestart() throws {
        let fromLastBoot = KeyboardPresence(
            hasFullAccess: true, recordedAt: start, bootIdentity: thisBoot &+ 1)
        let words = try XCTUnwrap(
            SetupState(presence: fromLastBoot, now: start + 1, bootIdentity: thisBoot)
                .unresolvedExplanation)
        XCTAssertTrue(words.contains("restarted"), words)
    }

    // MARK: Microphone

    /// Never asked is not the same as refused, and only one of the three is the
    /// user's to fix. The shipped `microphoneGranted = true` fails the first two.
    func testMicrophoneMapsAllThreePermissions() {
        XCTAssertEqual(state(nil, microphone: .granted).microphoneAccess, .confirmed)
        XCTAssertEqual(state(nil, microphone: .denied).microphoneAccess, .blocked)
        XCTAssertEqual(state(nil, microphone: .undetermined).microphoneAccess, .unknown)
    }

    /// The microphone is not one of the two requirements, so a blocked one cannot
    /// hold the card below "Ready to type". A keyboard extension has no microphone
    /// with or without Full Access; counting it would make the checklist
    /// unfinishable.
    func testTheMicrophoneIsNotCountedAsARequirement() {
        let setup = state(confirmed(), microphone: .denied)
        XCTAssertEqual(setup.microphoneAccess, .blocked)
        XCTAssertEqual(setup.requirementCount, 2)
        XCTAssertTrue(setup.isReady)
    }

    // MARK: The cloud model

    /// **Full Access buys the network. It does not buy somewhere to send.**
    ///
    /// The version this rejects is the one that shipped: `fullAccess == .confirmed
    /// ? "On — cloud rewrites and key clicks work" : …`, printed on Home under
    /// "Ready to type 2/2". On a stock install there is no backend URL in the
    /// shared store, so `BackendTransport.configured()` is nil, `RoutedIntelligence`
    /// has no cloud engine at all, and every Hebrew Fix, Rewrite, Tone and Reply
    /// fails — while this line says the thing they need is working.
    ///
    /// Both directions are asserted. A build that simply deleted the claim would
    /// pass the first and fail the second, and it would be a different defect:
    /// somebody who *has* set a backend up is entitled to be told so.
    func testFullAccessDoesNotClaimCloudRewritesWithNoCloudModel() {
        let withoutCloud = state(confirmed(), cloudConfigured: false).fullAccessDetail
        XCTAssertEqual(state(confirmed(), cloudConfigured: false).fullAccess, .confirmed)
        XCTAssertFalse(
            withoutCloud.localizedCaseInsensitiveContains("cloud rewrites and key clicks work"),
            "Home tells a phone with no backend that its cloud rewrites work: \(withoutCloud)")
        XCTAssertTrue(
            withoutCloud.contains(BackendTransport.settingsPath),
            "and it does not say where to fix it: \(withoutCloud)")

        let withCloud = state(confirmed(), cloudConfigured: true).fullAccessDetail
        XCTAssertTrue(
            withCloud.localizedCaseInsensitiveContains("cloud rewrites"),
            "a configured backend is no longer credited: \(withCloud)")
    }

    /// Unconfirmed Full Access says nothing about the cloud either way, because
    /// nothing about the cloud is what is standing in the user's way yet.
    func testAnUnconfirmedFullAccessDetailIsUnchangedByTheCloud() {
        XCTAssertEqual(
            state(nil, cloudConfigured: false).fullAccessDetail,
            state(nil, cloudConfigured: true).fullAccessDetail)
        XCTAssertEqual(state(nil).fullAccessDetail, "Typing and on-device AI work without it")
    }

    /// Onboarding's Full Access step listed "Cloud rewrites for languages the
    /// on-device model cannot handle" under "What it turns on", unconditionally, on
    /// screen 4 of 6 — before the user has any way of knowing a cloud model is a
    /// thing they need. Same fix, same test shape: the promise is allowed only
    /// where it is true.
    func testWhatFullAccessTurnsOnOnlyPromisesCloudRewritesWhenThereAreSome() {
        let withoutCloud = state(nil, cloudConfigured: false).fullAccessTurnsOn
        XCTAssertFalse(
            withoutCloud.localizedCaseInsensitiveContains("cloud rewrites"),
            "onboarding promises cloud rewrites to a phone with no cloud model: \(withoutCloud)")
        XCTAssertTrue(withoutCloud.contains(BackendTransport.settingsPath))

        XCTAssertTrue(
            state(nil, cloudConfigured: true).fullAccessTurnsOn
                .localizedCaseInsensitiveContains("cloud rewrites"))
    }

    /// **Onboarding's third Full Access row cost the user the choice they had made
    /// two screens earlier.** It read "Typing, autocorrect, predictions and emoji
    /// all run locally. Full Access is only for the cloud fallback", and without
    /// Full Access `SharedContainer.url` is nil, `SharedStore` falls back to
    /// `.standard`, and every setting the app wrote is invisible to the keyboard —
    /// the language list included, which leaves a French-only user typing on an
    /// English/Hebrew keyboard with no way to change it from inside one. It also
    /// contradicted the row directly above it, which credits Full Access with the
    /// key click sound.
    ///
    /// Both halves are asserted. A build that simply deleted the sentence would
    /// pass the first and fail the second, and that is a different defect: the row
    /// is titled "Works without it" and typing genuinely does.
    func testWorksWithoutFullAccessDoesNotClaimTheCloudIsAllThatStops() {
        let detail = SetupState.worksWithoutFullAccess

        XCTAssertFalse(
            detail.localizedCaseInsensitiveContains("only for the cloud"),
            "onboarding still says the cloud is the only thing Full Access buys: \(detail)")
        XCTAssertTrue(
            detail.localizedCaseInsensitiveContains("languages"),
            "and it does not warn that the language list never reaches the keyboard: \(detail)")
        XCTAssertTrue(
            detail.localizedCaseInsensitiveContains("key click"),
            "the row above credits Full Access with the key click; this one has to agree: \(detail)")
        XCTAssertTrue(
            detail.localizedCaseInsensitiveContains("typing"),
            "typing really does work without it, and the row is titled 'Works without it': \(detail)")
    }

    /// The same consequence, said beside the language picker. It names the two
    /// languages a keyboard with no shared container actually draws, so it is tied
    /// to the shipped default rather than to a remembered pair — if that default
    /// ever changes, this fails instead of quietly lying.
    func testTheLanguagePickerSaysWhatHappensWithoutFullAccess() {
        let note = SetupState.languagesNeedFullAccess
        XCTAssertTrue(note.localizedCaseInsensitiveContains("full access"))
        for language in SharedStore.shippedDefaultLanguages {
            XCTAssertTrue(
                note.contains(language.displayName),
                "the fallback the keyboard actually draws includes \(language.displayName): \(note)")
        }
    }

    /// The cloud is not a *requirement*, and must never become one here. Two ticks
    /// mean the keyboard is installed and permitted; a keyboard with no backend
    /// still types, still autocorrects, and still runs every AI action in the
    /// languages Apple's on-device model does list.
    func testTheCloudModelIsNotCountedAsARequirement() {
        let setup = state(confirmed(), cloudConfigured: false)
        XCTAssertEqual(setup.requirementCount, 2)
        XCTAssertEqual(setup.confirmedRequirements, 2)
        XCTAssertTrue(setup.isReady)
        XCTAssertNil(setup.unresolvedExplanation)
    }
}

/// One key, named once, and every dead end pointing at that name.
///
/// `cloudBackendURL` is read by three processes and, before this, was written by
/// one field titled "Where the screen is read". So a Hebrew rewrite failed with
/// "no cloud model is set up" and named nowhere, and the screen-context refusal
/// named a screen that had nothing to do with rewriting. These assert the property
/// that stops that recurring: the sentences are built from one constant.
final class CloudModelSettingNameTests: XCTestCase {

    /// The four failures that dead-end on the missing backend all name the same
    /// row. Each of these used to stop at "no cloud model is set up", or point at
    /// Screen Context, which is where a user goes to record their screen and not
    /// where they go when Hebrew Fix fails.
    func testEveryDeadEndNamesWhereTheCloudModelIsSetUp() {
        let messages: [(String, String)] = [
            ("unsupportedLanguage", AIEngineError.unsupportedLanguage(.hebrew).message),
            ("cloudNotConfigured", AIEngineError.cloudNotConfigured.message),
            ("deviceNotSupported", AIEngineError.deviceNotSupported.message),
            ("notConfigured", ScreenContextEndReason.notConfigured.recovery)
        ]
        for (name, message) in messages {
            XCTAssertTrue(
                message.contains(BackendTransport.settingsPath),
                "\(name) reports a missing cloud model and names nowhere to go: \(message)")
        }
    }

    /// The path has to be a path — a screen the app draws, reachable by the words
    /// in it. `CloudModelView` is the row; this is the half a unit test can hold,
    /// and it is what fails if somebody renames the row without renaming this.
    func testTheSettingsPathNamesTheSectionAndTheRow() {
        XCTAssertEqual(BackendTransport.settingsPath, "Settings › AI › Cloud model")
        XCTAssertTrue(BackendTransport.setUpRecovery.contains(BackendTransport.settingsPath))
    }

    /// The screen-context refusal no longer claims to be about screen reading
    /// alone, because the setting it is missing is not.
    func testTheScreenContextRefusalNamesTheCloudModel() {
        let explanation = ScreenContextEndReason.notConfigured.explanation
        XCTAssertTrue(
            explanation.localizedCaseInsensitiveContains("cloud model"),
            "the ending blames screen reading for a setting four other features share: \(explanation)")
        XCTAssertFalse(
            explanation.localizedCaseInsensitiveContains("in this build"),
            "there is a screen for this now, so it is not something the build withheld")
    }
}
