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
                // **This promised screen reading on the first screen every user
                // sees**: "Turn on screen context and the keyboard answers the
                // message you're looking at." It pointed at a control that is no
                // longer drawn — `FeatureFlags.screenCaptureReply` takes Home's
                // Screen Context card out of the v1 build — and at a capability
                // no part of which has ever run. What Reply does in v1 is answer
                // the message the user copied, so that is what the line says.
                //
                // **The words are `HomeView.replySteps`' and
                // `ScreenContextPrompt`'s, deliberately.** "CopyClip's Paste" is
                // one gesture, and a user who meets the keyboard's own refusal
                // first must not have to work out that it and this sentence are
                // describing the same thing. For the same reason neither of them
                // names where a key sits: CopyClip can be moved or removed in the
                // layout editor, and Reply's end of the suggestion bar is the
                // *leading* end, which is the right-hand one in Hebrew. The name
                // and the glyph come off `AIAction.reply` rather than being spelt
                // again here.
                InfoRow(
                    icon: AIAction.reply.icon,
                    title: "Answers the message you copied",
                    detail:
                        "Copy it, let it in with CopyClip's Paste, and \(AIAction.reply.title) writes the answer."
                )
                // This was a dictation promise — "Dictation that keeps up when you
                // switch language mid-sentence" — made when the mic key streamed a
                // fixed script. Dictation is real now and could go back, but the
                // claim would still be the unmeasured half: `Bar/dictation/` scores
                // 23.5% word error rate on code-switched speech against 8.5% English
                // and 10.7% Hebrew, so mid-sentence switching is the thing it is
                // *worst* at. The line stays out until that number says otherwise.
                //
                // **This said 17.7% until 2026-08-16, and no committed run produces
                // that number.** `harness/score.py` over the committed outputs
                // reproduces `Bar/dictation/README.md` exactly. The 17.7% set was
                // written in `d023520f`, the same commit that first committed the
                // scorer, so it predates the scoring rule that ships. Do not restore
                // it from git history.
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
            withAnimation(Theme.Motion.quick) { appeared = true }
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
