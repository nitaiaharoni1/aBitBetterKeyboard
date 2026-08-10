import AIKeyboardCore
import SwiftUI

struct WelcomeStep: View {
    @State private var appeared = false

    var body: some View {
        StepLayout(
            title: "One keyboard for how you actually write",
            subtitle:
                "Hebrew and English in the same sentence, fixed and rewritten without leaving the app you are in."
        ) {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                ValuePoint(
                    icon: "character.cursor.ibeam",
                    title: "Types in both languages at once",
                    detail:
                        "Predictions understand ‏אני אשלח לך את ה-document‏ without switching layouts."
                )
                ValuePoint(
                    icon: "sparkles",
                    title: "Fix and rewrite in one tap",
                    detail: "Small edits on the text in front of you, not a chatbot to talk to."
                )
                ValuePoint(
                    icon: "eye",
                    title: "Replies that read the room",
                    detail:
                        "Turn on screen context and the keyboard answers the message you're looking at."
                )
                // This was a dictation promise — "Dictation that keeps up when you
                // switch language mid-sentence" — made when the mic key streamed a
                // fixed script. Dictation is real now and could go back, but the
                // claim would still be the unmeasured half: `Bar/dictation/` scores
                // 17.7% word error rate on code-switched speech against 8-10% on
                // either language alone, so mid-sentence switching is the thing it
                // is *worst* at. The line stays out until that number says
                // otherwise.
                ValuePoint(
                    icon: "globe",
                    title: "Sixty-four keyboards, one swipe apart",
                    detail:
                        "Slide along the space bar to change language, and it names the one you land on."
                )
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 12)
            .onAppear {
                withAnimation(.easeOut(duration: 0.45).delay(0.1)) { appeared = true }
            }
        }
    }
}

struct ValuePoint: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.sm) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.Brand.gradient)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.Brand.softGradient)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.Text.primary)
                Text(detail)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.Text.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
