import AVFAudio
import AIKeyboardCore
import SwiftUI

// MARK: - SetupState measurement

/// The three measurements behind the setup card.
///
/// The reading of them is `SetupState` in `AIKeyboardShared`, where it can be
/// tested; this is the half that has to be here, because `AVAudioApplication` is
/// AVFoundation and that target is linked on its own by the broadcast extension.
///
/// The third is the cloud model, and it is a measurement rather than an
/// assumption for the same reason the first two are: the card used to print "cloud
/// rewrites work" off a green Full Access tick alone, which on a stock install is
/// the opposite of the truth.
extension SetupState {
    static func current(store: SharedStore = .shared) -> SetupState {
        let state = SetupState(
            presence: KeyboardPresence.load(),
            microphone: .current,
            // `isReady`, not `configured() != nil`: a build ships an address, so
            // the second is true before the token has been pasted in and this
            // screen would tick off a setup step the keyboard then 401s on.
            cloudConfigured: BackendTransport.isReady(defaults: store.userDefaults),
            cloudAllowed: store.allowsCloudAIProcessing,
            switchAcknowledged: store.hasAcknowledgedKeyboardSwitch)
        state.reportFirstConfirmations()
        return state
    }

    /// `full_access_confirmed` and `keyboard_added_confirmed`, reported from the
    /// measurement rather than from a screen.
    ///
    /// **This is the only place that sees every recompute, which is why it is
    /// here and not in a view.** Thirteen call sites across Home, Settings, Keys,
    /// Languages, Dictionary, the layout editor and onboarding recompute this on
    /// `onAppear` and on every return to the foreground, and the transition being
    /// counted can happen behind any one of them — the user leaves for iOS
    /// Settings, grants Full Access, and comes back to whichever tab they left.
    /// Putting the call on Home alone would miss them; putting it on all
    /// thirteen is thirteen chances for the fourteenth to be forgotten.
    ///
    /// **No latch here on purpose.** `Analytics.record` holds the
    /// once-per-install flag through `AnalyticsEvent.oncePerInstallKey`, so this
    /// stays a plain statement of what was just measured and there is exactly one
    /// implementation of "only ever once" to get wrong. That also makes this
    /// cheap enough to sit in a function called on every foreground: a
    /// `UserDefaults` bool read, after the first time.
    ///
    /// Both are reported rather than only the stronger one. `fullAccess` implies
    /// `keyboardAdded` today, since both are read off one `KeyboardPresence`
    /// record, but the policy joins the two events against `onboarding_completed`
    /// to tell "never added" from "added, never granted" — and that join needs
    /// both rows present, not one inferred from the other.
    private func reportFirstConfirmations() {
        if keyboardAdded == .confirmed { Analytics.record(.keyboardAddedConfirmed) }
        if fullAccess == .confirmed { Analytics.record(.fullAccessConfirmed) }
    }
}

extension MicrophonePermission {
    /// `AVAudioApplication.recordPermission` is the iOS 17 spelling and the iOS 26
    /// SDK still carries it undeprecated; the `AVAudioSession` property of the same
    /// name has been deprecated since iOS 17. Reading it prompts nothing.
    static var current: MicrophonePermission {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return .granted
        case .denied: return .denied
        default: return .undetermined
        }
    }
}

// MARK: - FullAccessNeededBanner

/// Sits on a surface that accepts a choice the keyboard cannot read yet —
/// the layout editor and the language picker, today — and says so at the
/// moment the choice is made, rather than leaving the user to discover it on
/// their phone.
///
/// **Deliberately not the `StatusRow` question mark.** `StatusRow` is a
/// checklist item: quiet, tertiary, one of several rows working through a
/// setup card. This is not a checklist — it sits beside a control the user
/// is about to use and will otherwise have no way to learn is inert, which
/// is why it carries real colour and a border rather than a caption's grey.
///
/// **Says "once Full Access is on", never "Full Access is off".**
/// `SetupState.fullAccess` can only ever *confirm* a yes — `KeyboardPresence`
/// is a file only a keyboard that already has the entitlement could have
/// written — so `!= .confirmed` also covers a phone where Full Access was
/// just switched on and the keyboard has not been opened once since. Naming
/// that as "off" would be wrong exactly there. Every string handed to this
/// view has to hold up under both readings, which is what `SetupState
/// .languagesNeedFullAccess` is already written to do.
struct FullAccessNeededBanner: View {
    let message: String

    /// Distinguishes this banner's accessibility identifier from any other
    /// on screen. Required rather than defaulted: `SettingsTypingSection` and
    /// `SettingsAISection` both draw one on the same scrollable Settings
    /// screen, and two elements answering to one identifier is a
    /// `firstMatch` that picks whichever it finds first — the exact trap
    /// `LayoutView`'s `remove-bar-…` / `add-bar-…` identifiers exist to avoid.
    let context: String

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.Semantic.warning)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(message)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Text.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Open Settings", action: openSettings)
                    .font(Theme.Fonts.caption.weight(.semibold))
                    .foregroundStyle(Theme.Semantic.warning)
            }
        }
        .padding(Theme.Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.Semantic.warning.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.Semantic.warning.opacity(0.35), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("full-access-needed-\(context)")
    }
}

// MARK: - StatusRow

struct StatusRow: View {
    let title: String
    let detail: String
    let check: SetupCheck
    var actionTitle = "Settings"
    var action: (() -> Void)?
    var singleLineDetail = false

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            Image(systemName: symbol)
                .font(.system(size: 18))
                .foregroundStyle(tint)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Theme.Fonts.body.weight(.medium))
                    .foregroundStyle(Theme.Text.primary)
                Text(detail)
                    .font(singleLineDetail ? Theme.Fonts.micro : Theme.Fonts.caption)
                    .foregroundStyle(Theme.Text.secondary)
                    .lineLimit(singleLineDetail ? 1 : nil)
                    .minimumScaleFactor(singleLineDetail ? 0.75 : 1)
                    .fixedSize(horizontal: false, vertical: !singleLineDetail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if check != .confirmed, let action {
                Button(actionTitle, action: action)
                    .font(Theme.Fonts.callout.weight(.medium))
                    .foregroundStyle(Theme.Brand.solid)
                    .padding(.horizontal, Theme.Space.sm)
                    .padding(.vertical, Theme.Space.xxs)
                    .background(Capsule().strokeBorder(Theme.Surface.separator, lineWidth: 1))
                    .buttonStyle(.borderless)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(spokenValue)
    }

    private var symbol: String {
        switch check {
        case .confirmed: return "checkmark.circle.fill"
        case .unknown: return "questionmark.circle"
        case .blocked: return "exclamationmark.circle.fill"
        }
    }

    private var tint: Color {
        switch check {
        case .confirmed: return Theme.Semantic.success
        case .unknown: return Theme.Text.tertiary
        case .blocked: return Theme.Semantic.warning
        }
    }

    private var spokenValue: String {
        switch check {
        case .confirmed: return "Done"
        case .unknown: return "Not checked yet"
        case .blocked: return "Needs attention"
        }
    }
}
