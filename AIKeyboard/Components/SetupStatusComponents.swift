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
        SetupState(
            presence: KeyboardPresence.load(),
            microphone: .current,
            // `isReady`, not `configured() != nil`: a build ships an address, so
            // the second is true before the token has been pasted in and this
            // screen would tick off a setup step the keyboard then 401s on.
            cloudConfigured: BackendTransport.isReady(),
            switchAcknowledged: store.hasAcknowledgedKeyboardSwitch)
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
