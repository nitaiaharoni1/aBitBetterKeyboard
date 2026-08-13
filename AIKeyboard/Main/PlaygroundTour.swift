import AIKeyboardCore
import SwiftUI

enum PlaygroundTourStep: Int, CaseIterable {
    case fix
    case rewrite
    case tone
    case suggestion
    case emoji
    case dictation
    case languageSwitch
    case reply
    case send

    var title: String {
        switch self {
        case .fix: return "Fix a message"
        case .rewrite: return "Rewrite it"
        case .tone: return "Change the tone"
        case .suggestion: return "Use a suggestion"
        case .emoji: return "Add an emoji"
        case .dictation: return "Try dictation"
        case .languageSwitch: return "Switch languages"
        case .reply: return "Reply from the screen"
        case .send: return "Send a message"
        }
    }

    var instruction: String {
        switch self {
        case .fix:
            return "Tap Fix to correct the sentence in the composer."
        case .rewrite:
            return "Tap Rewrite to get a few different ways to say it."
        case .tone:
            return "Press and hold Rewrite, then choose a tone."
        case .suggestion:
            return "Tap one of the words in the suggestion bar."
        case .emoji:
            return "Open Emoji, then choose one from the grid."
        case .dictation:
            return "Tap Record. If it is not running, the keyboard will show how to start it."
        case .languageSwitch:
            return "Swipe sideways across the space bar to switch languages."
        case .reply:
            return "Tap Reply to answer the sample message shown by the keyboard."
        case .send:
            return "Tap the orange send button. Then keep chatting as much as you like."
        }
    }

    var seedText: String {
        switch self {
        case .fix:
            return PlaygroundView.seedSentence
        case .rewrite:
            return "Can you send me the details when you get a chance"
        case .tone:
            return "Send me the report today"
        case .suggestion:
            return "hel"
        case .emoji, .dictation, .languageSwitch, .reply:
            return ""
        case .send:
            return "That was easy!"
        }
    }

    var expectedAIAction: AIAction? {
        switch self {
        case .fix: return .fix
        case .rewrite, .tone: return .rewrite
        case .reply: return .reply
        case .suggestion, .emoji, .dictation, .languageSwitch, .send:
            return nil
        }
    }

    var next: PlaygroundTourStep? {
        PlaygroundTourStep(rawValue: rawValue + 1)
    }
}

struct PlaygroundTourCard: View {
    let step: PlaygroundTourStep?
    let onSkip: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.sm) {
            Image(systemName: step == nil ? "checkmark.circle.fill" : "sparkles")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(step == nil ? Theme.Semantic.success : Theme.Brand.solid)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.Space.xs) {
                    Text(step?.title ?? "Tour complete")
                        .font(Theme.Fonts.headline)
                        .foregroundStyle(Theme.Text.primary)

                    Spacer(minLength: 0)

                    if let step {
                        Text("\(step.rawValue + 1) of \(PlaygroundTourStep.allCases.count)")
                            .font(Theme.Fonts.micro)
                            .foregroundStyle(Theme.Text.tertiary)
                    }
                }

                Text(step?.instruction ?? "You know the keyboard. Keep sending messages to try it.")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Text.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if step != nil {
                Button("Skip", action: onSkip)
                    .font(Theme.Fonts.caption.weight(.semibold))
                    .foregroundStyle(Theme.Brand.solid)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                    .offset(y: -11)
                    .accessibilityHint("Moves to the next playground task")
            }
        }
        .padding(.horizontal, Theme.Space.sm)
        .padding(.vertical, Theme.Space.xs)
        .background(Theme.Surface.raised)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.Surface.separator)
                .frame(height: 1)
        }
    }
}
