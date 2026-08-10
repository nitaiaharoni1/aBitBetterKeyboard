import SwiftUI

// MARK: - The strip

/// The row above the suggestion bar: what the keyboard is doing, and the answer
/// when it has one.
///
/// **It replaced two things and a panel.** `ScreenContextStrip` was a separate
/// 30pt row that appeared and disappeared with the capture session, and every AI
/// answer arrived in a panel that covered the keys — so the user could not see
/// what they had typed while choosing how to rewrite it, and the keyboard's height
/// changed twice per action. This is one strip, always present, and the keys are
/// never covered.
///
/// Its height is constant for the same reason the one-tap button's width is: a
/// strip that grows when an answer arrives moves the three candidates and the whole
/// keyboard under the user's thumb, mid-sentence.
public struct ActionBanner: View {

    @ObservedObject var controller: KeyboardController

    public init(controller: KeyboardController) {
        self.controller = controller
    }

    public var body: some View {
        HStack(spacing: Theme.Space.xs) {
            leading

            content

            Spacer(minLength: 0)

            trailing
        }
        .padding(.horizontal, Theme.Space.sm)
        .frame(height: Theme.Metrics.bannerHeight)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                .fill(surface)
                .padding(.horizontal, Theme.Space.xxs)
                .padding(.vertical, Theme.Space.xxs)
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

    var state: BannerState {
        BannerState.resolve(
            isDictating: controller.isDictating,
            dictationIsLive: controller.dictationAvailability.isLive,
            dictationTranscript: controller.dictationTranscript,
            dictationFailure: controller.dictationFailure,
            isWorking: controller.isWorking,
            runningAction: controller.runningAction,
            error: controller.aiError,
            block: controller.block,
            options: controller.bannerOptions,
            index: controller.bannerIndex,
            screenContext: controller.screenContext.context,
            // Screen context's own sentence when it has one — that is what is left
            // of `ScreenContextStrip` — and the ordinary instruction when it does
            // not. See `KeyboardController.screenContextHint`.
            idleHint: controller.screenContextHint ?? BannerState.defaultHint)
    }

    var surface: Color {
        switch state {
        case .hint: return Theme.Keys.panel.opacity(0.5)
        default: return Theme.Keys.panel
        }
    }
}
