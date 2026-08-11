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
            hero
                .opacity(appeared ? 1 : 0)
                .scaleEffect(appeared ? 1 : 0.92)

            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                InfoRow(
                    icon: "character.cursor.ibeam",
                    title: "Types in both languages at once",
                    detail:
                        "Predictions understand ‏אני אשלח לך את ה-document‏ without switching layouts."
                )
                InfoRow(
                    icon: "sparkles",
                    title: "Fix and rewrite in one tap",
                    detail: "Small edits on the text in front of you, not a chatbot to talk to."
                )
                InfoRow(
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
                InfoRow(
                    icon: "globe",
                    title: "Sixty-four keyboards, one swipe apart",
                    detail:
                        "Slide along the space bar to change language, and it names the one you land on."
                )
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 12)
        }
        .onAppear {
            withAnimation(Theme.Motion.quick.delay(0.1)) { appeared = true }
        }
    }

    /// The brand mark over the two scripts the keyboard is for. A picture
    /// rather than a fifth bullet: the four rows below carry the specifics,
    /// this carries the reason to read them. It is also the one place the
    /// brand gradient appears in onboarding — the product-identity moment
    /// every other step stays flat to protect.
    private var hero: some View {
        HStack {
            Spacer()
            ZStack {
                Circle()
                    .fill(Theme.Brand.softGradient)
                    .frame(width: 148, height: 148)

                Circle()
                    .fill(Theme.Brand.gradient)
                    .frame(width: 96, height: 96)

                // Not `SparkleMark`: that component always draws the brand
                // gradient, which would be invisible over the same gradient.
                Image(systemName: "sparkles")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(Theme.Text.onBrand)

                Text("א")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Theme.Text.primary)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Theme.Surface.raised))
                    .overlay(Circle().strokeBorder(Theme.Surface.separator, lineWidth: 1))
                    .offset(x: -58, y: -34)

                Text("A")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Theme.Text.primary)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Theme.Surface.raised))
                    .overlay(Circle().strokeBorder(Theme.Surface.separator, lineWidth: 1))
                    .offset(x: 58, y: 34)
            }
            Spacer()
        }
        .padding(.vertical, Theme.Space.xs)
        .accessibilityHidden(true)
    }
}
