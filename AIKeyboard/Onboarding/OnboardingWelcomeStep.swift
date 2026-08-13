import AIKeyboardCore
import SwiftUI

struct WelcomeStep: View {
    @State private var appeared = false

    var body: some View {
        StepLayout(
            title: "One keyboard for how you actually write",
            subtitle:
                "Hebrew and English in the same sentence, fixed and rewritten without leaving the app you are in.",
            circledWord: "write"
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
                    tint: Theme.Brand.solid,
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

    /// The graphite slab with the orange icon chip, over the two scripts the
    /// keyboard is for. A picture rather than a fifth bullet: the four rows
    /// below carry the specifics, this carries the reason to read them. It is
    /// onboarding's one hero moment — the same graphite-and-orange treatment
    /// the design direction gives a screen's feature card, with its top-edge
    /// highlight and ambient lift — and every other step stays flat to
    /// protect it.
    private var hero: some View {
        HStack {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.sheet, style: .continuous)
                    .fill(Theme.Keys.functionStrong)
                    .frame(width: 132, height: 132)
                    .graphiteTopHighlight(cornerRadius: Theme.Radius.sheet)
                    .ambientDepth()

                Image("BrandMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                Text("א")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Theme.Text.primary)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Theme.Surface.raised))
                    .overlay(Circle().strokeBorder(Theme.Surface.separator, lineWidth: 1))
                    .offset(x: -62, y: -40)

                Text("A")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Theme.Text.primary)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Theme.Surface.raised))
                    .overlay(Circle().strokeBorder(Theme.Surface.separator, lineWidth: 1))
                    .offset(x: 62, y: 40)
            }
            Spacer()
        }
        .padding(.vertical, Theme.Space.xs)
        .accessibilityHidden(true)
    }
}
