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
/// **Absent when idle.** The default "Type, or pick an action below" instruction
/// is what the action row already says by existing, so the strip is omitted until
/// there is a live reading, a model call, a refusal or a recording. Its height
/// while shown is still constant: a strip that grows when an answer arrives would
/// move the three candidates under the thumb mid-choice. The host height follows
/// presence; `KeyboardGeometry.ownUIHeightFraction` still reports the tallest form
/// so a mid-read resize cannot move the fingerprint band.
public struct ActionBanner: View {

    @ObservedObject var controller: KeyboardController

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
}
