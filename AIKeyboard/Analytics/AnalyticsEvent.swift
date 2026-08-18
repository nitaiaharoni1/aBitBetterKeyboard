import Foundation

/// The six events `.claude/docs/analytics-policy.md` decided on, and nothing else.
///
/// **This enum is the never-list made structural.** The policy's central promise is
/// that no event carries anything typed, corrected, dictated, or read off a screen,
/// "not in a property, not in a free-text field, not truncated, not hashed." A
/// promise written in a document is kept by whoever read it; a promise written as a
/// type is kept by the compiler. So there is no `case custom(String, [String: Any])`
/// here, no dictionary a caller fills in, and every associated value below is an
/// `Int`, a `Bool` or a closed enum. There is no slot a message could go in, which
/// is why adding one has to be a visible edit to this file rather than a call site
/// somebody writes in a hurry.
///
/// Adding a case is a change to the policy, not to this file. Read section 3 first.
enum AnalyticsEvent {

    /// Q1, the per-step funnel.
    ///
    /// The policy was written against a ten-step flow. The required path is three
    /// screens now (`OnboardingStep.required`), with five more offered at the end
    /// rather than blocking it, so a funnel read against this event answers a
    /// different and better question than it used to: how many people reach a
    /// working keyboard, rather than how many survive a tour. `index` is the
    /// position within whichever list the user is walking, so it is only
    /// meaningful beside `step`, never on its own.
    case onboardingStepAdvanced(index: Int, step: Step, via: Advance)

    /// Q1's tail. `skippedStepCount` is how many steps were passed with Skip
    /// rather than Continue, which is the difference between a user who read the
    /// flow and one who dismissed it.
    case onboardingCompleted(skippedStepCount: Int)

    /// Q2's grant side. Fires once per install, on the first recompute that reads
    /// `SetupState.fullAccess == .confirmed`.
    case fullAccessConfirmed

    /// Q2's other half. Joined against `onboardingCompleted` with neither this nor
    /// `fullAccessConfirmed` present, it separates "never added the keyboard" from
    /// "added it, never granted Full Access" — the two failures
    /// `SetupState.unresolvedExplanation` cannot tell apart from inside the app.
    case keyboardAddedConfirmed

    /// Q5, read as *companion app* retention and never as keyboard retention. The
    /// policy is explicit that a happy daily user who set up once and never
    /// reopened the app reads as churned here, and that this event must never be
    /// relabelled to hide that.
    case appSessionStarted(daysSinceInstall: Int)

    /// Q3's answerable half: does anybody start a real capture session at all.
    /// Only `ScreenContextSource.capture` counts. The scripted sample is a demo
    /// and firing on it would answer a question nobody asked.
    ///
    /// Dormant while `FeatureFlags.screenCaptureReply` is false, because the entry
    /// points that could raise a real session are not in the build. Kept rather
    /// than deleted: the flag is a dated hold on shipping the feature, not a
    /// decision to stop measuring it, and a policy-approved event removed and
    /// re-added later is a second trip through the same review.
    case screenContextSessionStarted

    /// The wire name. Fixed strings, written out rather than derived from the case
    /// name, so renaming a Swift case cannot silently split a funnel in two.
    var name: String {
        switch self {
        case .onboardingStepAdvanced: "onboarding_step_advanced"
        case .onboardingCompleted: "onboarding_completed"
        case .fullAccessConfirmed: "full_access_confirmed"
        case .keyboardAddedConfirmed: "keyboard_added_confirmed"
        case .appSessionStarted: "app_session_started"
        case .screenContextSessionStarted: "screen_context_session_started"
        }
    }

    /// Everything besides the envelope. Empty for the three events the policy gives
    /// no properties.
    var properties: [String: AnalyticsValue] {
        switch self {
        case .onboardingStepAdvanced(let index, let step, let via):
            ["step_index": .int(index), "step_name": .string(step.rawValue), "via": .string(via.rawValue)]
        case .onboardingCompleted(let skipped):
            ["skipped_step_count": .int(skipped)]
        case .appSessionStarted(let days):
            ["days_since_install": .int(days)]
        case .fullAccessConfirmed, .keyboardAddedConfirmed, .screenContextSessionStarted:
            [:]
        }
    }

    /// Which of the events may only ever be sent once for an install.
    ///
    /// Both are transitions of a state the app recomputes on every return to the
    /// foreground, so without a latch they would fire on every app switch and the
    /// grant *rate* would read as a grant *count*.
    var oncePerInstallKey: String? {
        switch self {
        case .fullAccessConfirmed: "analytics.sent.full_access_confirmed"
        case .keyboardAddedConfirmed: "analytics.sent.keyboard_added_confirmed"
        default: nil
        }
    }

    // MARK: The closed vocabularies

    /// Every screen the flow has ever had a name for, which is no longer the same
    /// as the screens it runs.
    ///
    /// A raw-value enum rather than a `String` parameter, so a call site cannot
    /// invent an eleventh step name and a query written against this list cannot
    /// silently miss a step that was renamed.
    ///
    /// **Three of these are the required path and five are optional; two are
    /// currently emitted by nothing.** `OnboardingStep.required` is welcome,
    /// addKeyboard and practiceWriting; `OnboardingStep.extras` is palette,
    /// languages, microphone, practiceEveryday and practiceSmartTools, reached
    /// only by asking for them at the end. `OnboardingStep.event` is the one
    /// mapping from screen to name, and it produces none of:
    ///
    /// - `fullAccess`, because the standalone Full Access step is gone. The
    ///   permission is now asked at the moment it buys something (NIT-15), so
    ///   there is no screen whose advance means "read the Full Access page". The
    ///   grant itself is still measured, by `fullAccessConfirmed`, which is the
    ///   event that actually mattered.
    /// - `switchConfirmation`, because confirming the globe key folded into
    ///   `addKeyboard`. The measurement did **not** disappear with the screen:
    ///   that advance is still recorded with `Advance.switchConfirmed`, so
    ///   "reached the add-keyboard step" and "actually proved the switch works"
    ///   stay distinguishable.
    ///
    /// **Both cases are kept rather than deleted.** A funnel query written against
    /// the ten names still parses, and a reader comparing a run from before this
    /// cut against one from after can see which names stopped appearing instead of
    /// finding an enum that never mentioned them. Deleting a name is how two
    /// datasets silently stop being comparable.
    enum Step: String {
        case welcome
        case palette
        case languages
        case addKeyboard = "add_keyboard"
        case fullAccess = "full_access"
        case switchConfirmation = "switch_confirmation"
        case microphone
        case practiceWriting = "practice_writing"
        case practiceEveryday = "practice_everyday"
        case practiceSmartTools = "practice_smart_tools"
    }

    /// How a step was left. `switchConfirmed` is its own value because on the
    /// switch step the primary action *is* the confirmation, so counting it as an
    /// ordinary Continue would lose the one thing that step measures.
    enum Advance: String {
        case `continue`
        case skip
        case switchConfirmed = "switch_confirmed"
    }
}

/// The only shapes a property may take.
///
/// `.string` exists for the two closed vocabularies above and is unreachable from
/// anywhere else, because `AnalyticsEvent.properties` is the only thing that builds
/// one and every string it passes comes from an enum's raw value.
enum AnalyticsValue: Encodable, Sendable {
    case int(Int)
    case bool(Bool)
    case string(String)

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        }
    }
}
