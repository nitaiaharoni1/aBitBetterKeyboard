import SwiftUI

/// Where each key ended up, keyed by `KeySpec.id`, in `KeyboardView.frameSpace`.
///
/// Published only so the layout editor can put a selection ring and a drop target
/// over the *real* keyboard rather than over a drawing of one. Nothing in the
/// keyboard itself reads this, and it costs one `GeometryReader` per key in a
/// background that draws nothing.
public struct KeyFramesKey: PreferenceKey {
    public static var defaultValue: [String: CGRect] { [:] }
    public static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// The whole keyboard: suggestion strip, key grid, and whatever panel is covering
/// the grid right now.
public struct KeyboardView: View {

    /// The coordinate space `KeyFramesKey` reports in. It is this view's own
    /// bounds, so an `.overlay` on a `KeyboardView` shares it exactly.
    public static let frameSpace = "aikeyboard-frames"

    // Internal so `KeyboardView+Keys` (and any later split) can read it. Private
    // would compile only while the keys lived in this same file.
    @ObservedObject var controller: KeyboardController
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    public init(controller: KeyboardController) {
        self.controller = controller
    }

    public var body: some View {
        VStack(spacing: 0) {
            // **One strip when there is something to say, nothing the rest of the
            // time — and "the rest of the time" now includes the two states it was
            // most often up for.** `ScreenContextStrip` occupied a 30pt row only
            // while a capture session was live, and every AI answer arrived in a
            // panel over the keys; the banner was both. A running call is the
            // progress bar below instead, and a live recording is the microphone
            // key drawn in record red, so what is left here is a live reading, a
            // refusal and a failure. See `BannerState.isPresented`.
            if controller.showsActionBanner {
                ActionBanner(controller: controller)
                    .transition(.opacity)
            }

            // Between the banner and the candidates, and present in every state:
            // three points reserved so a call starting cannot move the keys, and
            // a taller waveform while the microphone is open. See `WorkingProgressBar`.
            WorkingProgressBar(controller: controller)

            SuggestionBar(controller: controller)

            // **Nothing covers the whole key area any more.** This was a `ZStack`
            // with a `fullKeyAreaPanel` over it, and the three panels that used it —
            // the AI menu, the AI result and dictation — are deleted: every one of
            // them existed to say something the strip above now says, and they said
            // it with the keyboard hidden. What is left of overlays lives inside
            // `keyGrid`: the emoji grid replaces the letters and leaves the action
            // row above them, and emoji search hands the letters back and takes
            // only that row.
            keyGrid
                .frame(height: Theme.Metrics.keyAreaHeight(for: controller.customization))
        }
        .background(Theme.Keys.background)
        .environment(\.layoutDirection, controller.language.layoutDirection)
        .coordinateSpace(name: Self.frameSpace)
        .animation(Theme.Motion.quick, value: controller.showsActionBanner)
        .onAppear { Feedback.prepare() }
    }

    /// How the emoji grid arrives. Still needed by `KeyboardView+Keys`, which is the
    /// one place left that puts anything over the keys.
    var panelTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .opacity
        )
    }
}

/// Width of `KeyboardView` in `frameSpace`, so a long-press strip can stay on screen.
private struct KeyboardCanvasWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var keyboardCanvasWidth: CGFloat {
        get { self[KeyboardCanvasWidthKey.self] }
        set { self[KeyboardCanvasWidthKey.self] = newValue }
    }
}

extension View {
    /// Side inset, optional one-handed width, and the left-to-right pin every key
    /// row needs. Shared by the letter block and the action row; the emoji panel
    /// below the action row uses the same width and reach, without the key inset.
    func keyboardGridChrome(width: CGFloat, reach: Reach) -> some View {
        // **Every row is drawn in the order its keys are listed, in every
        // language, and the letters plane is not an exception.** It was, and
        // that shipped all six right-to-left keyboards mirrored: the rows come
        // out of Apple's own layout data in physical key order, which is
        // already the order Apple draws them on screen — ק at the left of the
        // Hebrew top row, ض at the left of the Arabic one — and an RTL `HStack`
        // draws its first element last, so it reversed rows that were right.
        // `Bar/layouts/stock-rendered-rows.json` is the measurement and
        // `RenderedRowOrderTests` is what holds this to it.
        padding(.horizontal, Theme.Metrics.sideInset)
            .frame(width: width)
            // Which edge a narrowed grid hugs.
            .frame(maxWidth: .infinity, alignment: reachAlignment(reach))
            // **Applied last, so it covers the frame above as well as the rows.**
            // `.leading` and `.trailing` resolve against the layout direction in
            // force *where the modifier sits*, so with this pinned only around the
            // `VStack` a one-handed Hebrew keyboard hugged the wrong side — the
            // rows were right and the box holding them was mirrored. One-handed is
            // about which thumb is holding the phone, and that does not swap with
            // the script.
            .environment(\.layoutDirection, .leftToRight)
    }

    /// Where the grid sits when it has been narrowed for one hand. Physical
    /// sides, guaranteed by the `.leftToRight` pin this is resolved inside.
    func reachAlignment(_ reach: Reach) -> Alignment {
        switch reach {
        case .full: return .center
        case .left: return .leading
        case .right: return .trailing
        }
    }
}

// MARK: - Previews

#if DEBUG

/// Holds the controller in a `@StateObject` for the same reason the in-app
/// playground does: `KeyboardView` takes its controller as an
/// `@ObservedObject`, so something outside the view has to own it or a canvas
/// re-render rebuilds the keyboard's entire state mid-edit.
///
/// What a preview cannot show is the extension talking to a *host* app, which is
/// the half that broke on the first real install — see
/// `KeyboardController.preview(language:text:)`.
private struct KeyboardPreviewHost: View {

    @StateObject private var controller: KeyboardController

    init(language: KeyboardLanguage, text: String) {
        _controller = StateObject(
            wrappedValue: .preview(language: language, text: text))
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            KeyboardView(controller: controller)
        }
        .task { controller.refreshSuggestions() }
    }
}

#Preview("English") {
    KeyboardPreviewHost(language: .english, text: "the quick brown fo")
}

/// Hebrew is here because right-to-left rows are **not** mirrored, and a
/// preview is the cheapest place to see that they are not. See
/// `.claude/rules/keyboard-layout.md`.
#Preview("Hebrew") {
    KeyboardPreviewHost(language: .hebrew, text: "שלו")
}

#endif
