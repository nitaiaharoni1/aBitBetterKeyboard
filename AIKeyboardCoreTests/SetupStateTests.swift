import XCTest

@testable import AIKeyboardCore
@testable import AIKeyboardShared

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
        cloudConfigured: Bool = false,
        switchAcknowledged: Bool = false
    ) -> SetupState {
        SetupState(
            presence: presence, microphone: microphone, cloudConfigured: cloudConfigured,
            switchAcknowledged: switchAcknowledged,
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

    // MARK: The globe switch

    /// The app cannot measure which keyboard is on screen, so this row is the one
    /// self-reported answer on the card: it ticks when the user confirms and shows
    /// a question mark until then. It must never render `.blocked` — the app has
    /// no way to know the user has *not* switched — and never hold the card below
    /// ready, because it is not a fact the app can check.
    func testTheGlobeSwitchIsSelfReportedAndNeverBlocksReadiness() {
        let unconfirmed = state(confirmed())
        XCTAssertEqual(unconfirmed.keyboardSwitched, .unknown)
        XCTAssertTrue(unconfirmed.isReady)
        XCTAssertEqual(unconfirmed.confirmedRequirements, 2)

        let acknowledged = state(confirmed(), switchAcknowledged: true)
        XCTAssertEqual(acknowledged.keyboardSwitched, .confirmed)
        XCTAssertEqual(acknowledged.requirementCount, 2)
        XCTAssertEqual(acknowledged.confirmedRequirements, 2)
    }

    /// Until the user confirms, the row's job is to name the gesture. A detail
    /// that just said "not confirmed" would leave the user staring at a question
    /// mark with no idea what it is asking for.
    func testTheGlobeSwitchDetailNamesTheGesture() {
        let detail = state(nil).keyboardSwitchedDetail
        XCTAssertTrue(
            detail.localizedCaseInsensitiveContains("globe"),
            "the unconfirmed state never says what to do: \(detail)")
        XCTAssertTrue(
            detail.contains("aBitBetterKeyboard"),
            "and never says which keyboard to pick: \(detail)")
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
        // **The remedy moved, so this asserts the new one rather than being
        // deleted.** It used to require `settingsPath`, because being unconfigured
        // meant an address with no access token beside it and that screen held the
        // box. `AppAttestation` fills the bearer now and the box is gone from
        // Release, so naming a settings screen would send somebody to one that
        // offers them nothing. What must still be true is that the sentence says
        // what happens next: a build that answered the state and stopped is the
        // defect this half of the test has always been for.
        XCTAssertTrue(
            withoutCloud.localizedCaseInsensitiveContains("connect"),
            "and it does not say what would fix it: \(withoutCloud)")

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
        // Same move as `fullAccessDetail`: the remedy is the connection this app
        // makes for itself, not a settings screen that no longer holds a field.
        XCTAssertTrue(withoutCloud.localizedCaseInsensitiveContains("connection"))

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
