import SwiftUI

// MARK: - The strip

/// The row above the suggestion bar: what the keyboard is doing, and the answer
/// when it has one.
///
/// **It replaced two things and a panel.** `ScreenContextStrip` was a separate
/// 30pt row that appeared and disappeared with the capture session, and every AI
/// answer arrived in a panel that covered the keys — so the user could not see
/// what they had typed while choosing how to rewrite it. This is one strip for
/// every active moment, and the keys are never covered.
///
/// **Absent unless it has a sentence.** It is drawn for a live reading, a refusal,
/// a content failure and an answer nothing could apply, and for nothing else.
/// An engine that cannot run (`modelNotReady`, a 401, Apple Intelligence off)
/// is not a sentence: the orbit on the key ending is the signal. The default
/// "Type, or pick an action below" instruction is what the action row already says
/// by existing — and a **model call** and a **live recording**, which were the two
/// states this was up for most, now report on the control that started them: a
/// orbit on the action key, and a waveform on the microphone. A 69pt row that
/// appeared on a tap and left on the answer was relaying out the whole keyboard
/// twice per Fix.
///
/// Its height while shown is still constant: a strip that grew when an answer
/// arrived would move the three candidates under the thumb mid-choice. The host
/// height follows presence; `KeyboardGeometry.ownUIHeightFraction` still reports
/// the tallest form so a mid-read resize cannot move the fingerprint band.
public struct ActionBanner: View {

    @ObservedObject var controller: KeyboardController
    @Environment(\.dynamicTypeSize) var dynamicTypeSize

    public init(controller: KeyboardController) {
        self.controller = controller
    }

    public var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.xs) {
            leading

            content

            Spacer(minLength: 0)

            trailing
        }
        // **Both ends, and only the trailing one was ever set.** The surface was
        // inset 8pt from the right and flush against the left edge of the screen,
        // so the card looked like a panel that had been slid off the side — and
        // the recording tag sat hard against the bezel with the waveform running
        // out from under it. Every other band in this keyboard is inset on both
        // ends (`keyboardGridChrome`), so this was the one row that was not.
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, Theme.Space.xxs)
        .frame(maxWidth: .infinity)
        .frame(height: Theme.Metrics.bannerHeight)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                .fill(surface)
                .padding(.horizontal, Theme.Space.xs)
                .padding(.top, Theme.Space.xxs)
                .padding(.bottom, Theme.Space.xxs)
        )
        // **Pinned, like every other control row in this keyboard.** The label,
        // the paging dots and the Use button are targets, and a slide along the
        // space bar changes language mid-use: the bar's own chrome and then its
        // candidates were both pinned after exactly that moved them under a
        // thumb. See `.claude/rules/keyboard-layout.md`. The generated *text*
        // still reads in its own direction — that is set on the `Text` itself,
        // from the answer's language rather than the keyboard's.
        .environment(\.layoutDirection, .leftToRight)
        .animation(Theme.Motion.content, value: state)
        .accessibilityElement(children: .contain)
    }

    var state: BannerState { controller.bannerState }

    var surface: Color {
        switch state {
        case .hint: return Theme.Keys.panel.opacity(0.5)
        default: return Theme.Keys.panel
        }
    }

    // MARK: Dynamic Type

    /// The strip's small uppercase and secondary labels — the leading tag, a
    /// context sender, an options label — scale with Dynamic Type up to
    /// `Theme.Glyph.lightFloor`, the same badge ceiling every small label in
    /// this keyboard now shares. **Not the strip's own sentence**: that gets
    /// more room in `sentenceFontSize`, because it is what the banner exists
    /// to say and a badge-sized cap on it would waste most of the growth an
    /// AX5 user asked for.
    static func badgeFontSize(base: CGFloat, dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        min(base * Theme.DynamicType.scale(for: dynamicTypeSize), Theme.Glyph.lightFloor)
    }

    /// The strip's own sentence — an answer, a refusal, a failure — capped at
    /// 3pt over its shipped size rather than a fraction of the box.
    ///
    /// **`Theme.Metrics.bannerHeight` is fixed at 58 for the screen-context
    /// fingerprint** (`.claude/rules/screen-context.md`: growing it costs a
    /// conversation switch), and the worst case here already stacks a title
    /// over two lines of detail — three lines in 58pt at the shipped size.
    /// Scaling that trio by the full Dynamic Type ratio would push the third
    /// line past the strip well before AX5. `minimumScaleFactor`, already on
    /// every caller, is the same lever this file used before Dynamic Type
    /// existed to keep a long generated reply inside one line; a modest,
    /// fixed ceiling here is what keeps that lever from having to do all the
    /// work by itself.
    static func sentenceFontSize(base: CGFloat, dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        min(base * Theme.DynamicType.scale(for: dynamicTypeSize), base + 3)
    }
}
