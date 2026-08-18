import AIKeyboardCore
import SwiftUI

/// **`writing` is the third and last required step; the other two are optional.**
/// The required path ends at a keystroke, and this is the stage that produces
/// one — a seeded sentence, and Fix sitting over it. `everyday` and `smartTools`
/// run the same `PlaygroundTourStep` tasks the Playground guides, so they are
/// offered at the end rather than walked through on the way in. See
/// `OnboardingFlow`.
enum OnboardingPracticeStage: Int, CaseIterable {
    case writing
    case everyday
    case smartTools

    var title: String {
        switch self {
        case .writing: return "Improve your writing"
        case .everyday: return "Type your way"
        case .smartTools: return "Try the smart tools"
        }
    }

    var tasks: [PlaygroundTourStep] {
        switch self {
        case .writing: return [.fix, .rewrite, .tone]
        case .everyday: return [.suggestion, .emoji, .languageSwitch]
        case .smartTools: return [.dictation, .reply, .send]
        }
    }

    var seedText: String {
        switch self {
        case .writing: return PlaygroundTourStep.fix.seedText
        case .everyday: return PlaygroundTourStep.suggestion.seedText
        case .smartTools: return ""
        }
    }

    var instruction: String {
        switch self {
        case .writing:
            return "Start with Fix. Then tap Rewrite, or hold it to choose a tone."
        case .everyday:
            return "Tap a suggestion, open Emoji, or swipe across Space to change languages."
        case .smartTools:
            // **"Tap Record or Reply to see their setup guidance" was true of
            // both and is now true of one.** Reply's setup used to be a screen
            // broadcast; in v1 it reads what the user let in with CopyClip's
            // Paste, so tapping it here shows that sentence rather than a
            // permission to arrange. Dictation genuinely still needs something
            // outside this keyboard, and says so.
            return "Tap Record to see what dictation needs, or Reply to see how a message gets in."
        }
    }
}

struct TryItStep: View {
    let setup: SetupState
    let stage: OnboardingPracticeStage

    /// "The same keyboard you just installed" is true only for the user who did
    /// the setup step; Skip is on it, so the other path reaches this screen
    /// having installed nothing. The app can tell which, so it says which — and
    /// the skipped version has to make clear that this preview is not the
    /// keyboard appearing in other apps yet, or the next disappointment is
    /// discovering it is not there.
    private var subtitle: String {
        if stage == .everyday {
            return "These are the same guided tasks waiting for you in the Playground."
        }
        if stage == .smartTools {
            // **The two stopped being the same kind of thing.** This said both
            // "connect to features outside the keyboard", which was written when
            // Reply meant a screen broadcast started from the app. It reads the
            // message the user copied now, which happens entirely inside the
            // keyboard; dictation is still split, because iOS does not let a
            // keyboard extension open a microphone.
            return "The microphone is held by the app. Reply answers the message you copied."
        }
        return setup.keyboardAdded == .confirmed
            ? "The same keyboard you just installed, running inside the app."
            : "This preview works now. Add the keyboard in Settings to use it in other apps."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(stage.title)
                    .font(Theme.Fonts.display)
                    .tracking(-0.5)
                    .foregroundStyle(Theme.Text.primary)

                Text(subtitle)
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.Text.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: Theme.Space.xs) {
                    ForEach(stage.tasks, id: \.rawValue) { task in
                        Text(task.title)
                            .font(Theme.Fonts.micro)
                            // Not `Brand.solid`, which measures 2.51:1 against
                            // this chip's own 14% brand tint in light mode — for
                            // micro text, which wants 4.5. The tint carries the
                            // brand; the label only has to be readable, and
                            // `Text.primary` is 11.5:1 light and 10.6:1 dark.
                            .foregroundStyle(Theme.Text.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, Theme.Space.xs)
                            .padding(.vertical, 6)
                            .background(Theme.Brand.softGradient)
                            .clipShape(Capsule())
                    }
                }
                .padding(.top, Theme.Space.xs)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "Tasks: \(stage.tasks.map(\.title).joined(separator: ", "))"
                )
            }
            .padding(.horizontal, Theme.Space.lg)
            .padding(.top, Theme.Space.xl)

            KeyboardPreview(
                seedText: stage.seedText,
                placeholder: PlaygroundView.seedPlaceholder,
                hint: stage.instruction
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .padding(.horizontal, Theme.Space.xs)
        }
    }
}
