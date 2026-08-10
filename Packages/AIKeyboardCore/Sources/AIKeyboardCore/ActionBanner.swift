import SwiftUI

// MARK: - One thing the banner can offer

/// A generated answer the user can accept with one tap.
///
/// The three AI actions produce three differently-shaped results — one corrected
/// sentence, three rewrites labelled by the decision each takes, three replies
/// labelled by intent — and the banner shows one thing at a time. Flattening them
/// here rather than teaching the view about `RewriteVariant` and `ReplyOption`
/// separately is what keeps the paging, the Use button and the accessibility
/// wording written once.
public struct BannerOption: Identifiable, Equatable, Sendable {
    public let id: UUID
    /// The short uppercase tag over the text: an intent, a decision, a register.
    /// Empty for Fix, which has exactly one answer and nothing to distinguish it
    /// from.
    public let label: String
    public let text: String
    /// Which way to lay the text out. A reply to a Hebrew message is Hebrew
    /// whatever the keyboard is currently set to, so this comes from the answer
    /// rather than from `KeyboardController.language`.
    public let language: KeyboardLanguage

    public init(id: UUID = UUID(), label: String, text: String, language: KeyboardLanguage) {
        self.id = id
        self.label = label
        self.text = text
        self.language = language
    }
}

// MARK: - What the banner is saying

/// Everything the strip above the suggestion bar can be showing, as one value.
///
/// **One enum rather than a view that reads six published properties, because the
/// six disagree.** `isWorking`, `aiError`, `variants`, `replies`, `aiResultText`
/// and `isDictating` are set and cleared by different code paths, and a view
/// branching on them in sequence renders whichever it tested first: a failed call
/// that left `variants` populated from the previous action showed the old answer
/// under the new action's name. Resolving once, in one ordered place, is what
/// makes "which of these wins" a decision with a test on it rather than the order
/// somebody happened to write the `if`s in.
public enum BannerState: Equatable {

    /// Nothing has been asked for. Carries what to say about that, which is the
    /// message on screen when there is one and an instruction when there is not.
    case hint(String)

    /// A live screen-context reading. This is the idle state that earns the
    /// banner's height: it is what `ScreenContextStrip` used to occupy a separate
    /// 30pt row to say.
    case context(sender: String, message: String, language: KeyboardLanguage)

    /// A model call is in flight.
    case working(AIAction)

    /// Answers came back. `index` is which one is showing.
    case options(action: AIAction, options: [BannerOption], index: Int)

    /// The call failed for a reason the user can read. `AIEngineError` already
    /// separates title from message; only the title fits on one line, and the
    /// message is what the accessibility label carries.
    case failed(action: AIAction, title: String, detail: String)

    /// Reply was tapped with nothing behind it. Distinct from `.failed` because
    /// the tap has somewhere to go: the setup panel, which holds the broadcast
    /// picker and cannot be a banner.
    case needsSetup(String)

    /// A recording is open in the containing app. The keyboard cannot start one —
    /// see `DictationSession` — so this state is only ever reached from one that
    /// could.
    case dictating(transcript: String, isListening: Bool)

    /// A recording finished and produced nothing to insert.
    ///
    /// **Its own case because the alternative was silence.** The panel this
    /// replaced stayed on screen after a failed recording precisely so it could
    /// say why — `DictationKeyboardTests` pins that a recording with no speech in
    /// it "inserts nothing and says why". Routing a live session to the banner
    /// took the panel away, and without this the user tapped Stop, watched the
    /// waveform vanish and got no text and no reason.
    case dictationFailed(String)

    /// Resolves the state from everything that could be true at once.
    ///
    /// **The order of these branches is the whole point and it is not
    /// alphabetical.** Dictation outranks a model call because a recording is
    /// running in another process and stopping it is time-critical. A failure
    /// outranks options because a failed call can leave the previous action's
    /// answers in place. Work outranks both results and failure because
    /// `beginWork` clears `aiError` and sets `isWorking` in the same breath, and a
    /// retry must not flash the previous failure. Everything else is idle.
    public static func resolve(
        isDictating: Bool,
        dictationIsLive: Bool,
        dictationTranscript: String,
        dictationFailure: String,
        isWorking: Bool,
        runningAction: AIAction?,
        error: AIEngineError?,
        /// A result panel is open and owns this answer. The Tone row of
        /// `AIMenuPanel` still runs a rewrite into `AIResultPanel`, and the strip
        /// must not narrate a call the user is already watching in a panel — nor
        /// report "nothing came back" about one, which is what the empty-result
        /// branch below would otherwise do for the whole of it.
        resultsShownElsewhere: Bool,
        needsScreenContextSetup: Bool,
        options: [BannerOption],
        index: Int,
        screenContext: ScreenContext?,
        idleHint: String
    ) -> BannerState {
        // Ahead of the live check, not inside it: `stopDictation` clears
        // `isDictating` before the reason lands, so a failure tested second is a
        // failure never shown.
        if !dictationFailure.isEmpty, dictationTranscript.isEmpty, dictationIsLive || isDictating {
            return .dictationFailed(dictationFailure)
        }
        if isDictating || dictationIsLive {
            return .dictating(transcript: dictationTranscript, isListening: isDictating)
        }
        if resultsShownElsewhere { return idle(screenContext, idleHint) }

        // A running action is what names every branch below, so an action-shaped
        // state without one is not renderable. It cannot happen — `beginWork` sets
        // it — and falling through to the hint rather than force-unwrapping is
        // what keeps that a cosmetic bug rather than a crash in a keyboard.
        guard let runningAction else { return idle(screenContext, idleHint) }

        if isWorking { return .working(runningAction) }
        if needsScreenContextSetup { return .needsSetup(ScreenContextPromptTitle) }
        if let error {
            return .failed(action: runningAction, title: error.title, detail: error.message)
        }
        if !options.isEmpty {
            return .options(
                action: runningAction,
                options: options,
                index: min(max(0, index), options.count - 1))
        }
        // **An action that finished, raised no error and produced nothing.** The
        // banner used to fall through to the idle hint here, so a model answering
        // with an empty string left the strip reading "Type, or pick an action
        // below" — the user taps Fix, waits through the shimmer, and the keyboard
        // ends up looking exactly as it did before they touched it. An empty result
        // is the one outcome a user cannot act on or explain, which is the whole
        // reason `aiError` exists; this is the gap it does not cover, because
        // nothing threw.
        return .failed(
            action: runningAction,
            title: "Nothing came back",
            detail: "The model answered with nothing. Try again, or edit it yourself.")
    }

    private static func idle(_ context: ScreenContext?, _ hint: String) -> BannerState {
        guard let context else { return .hint(hint) }
        return .context(
            sender: context.sender, message: context.message, language: context.language)
    }

    /// What the strip says when it has nothing of its own to say.
    ///
    /// Names the row rather than a glyph, for the reason `SuggestionBar
    /// .aiButtonName` exists: the controls it points at are configurable, so it
    /// must not claim a particular one is in a particular place.
    public static let defaultHint = "Type, or pick an action below"
}

/// The one-line version of `ScreenContextPrompt.title`, which is three sentences
/// long because it lives in a panel with room for them.
private let ScreenContextPromptTitle = "Screen context is off"

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

    @ObservedObject private var controller: KeyboardController

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

    private var state: BannerState {
        BannerState.resolve(
            isDictating: controller.isDictating,
            dictationIsLive: controller.dictationAvailability.isLive
                && controller.overlay != .dictation,
            dictationTranscript: controller.dictationTranscript,
            dictationFailure: controller.dictationFailure,
            isWorking: controller.isWorking,
            runningAction: controller.runningAction,
            error: controller.aiError,
            resultsShownElsewhere: Self.resultPanelIsOpen(controller.overlay),
            needsScreenContextSetup: controller.overlay == .aiResult(.needsScreenContext),
            options: controller.bannerOptions,
            index: controller.bannerIndex,
            screenContext: controller.screenContext.context,
            // Screen context's own sentence when it has one — that is what is left
            // of `ScreenContextStrip` — and the ordinary instruction when it does
            // not. See `KeyboardController.screenContextHint`.
            idleHint: controller.screenContextHint ?? BannerState.defaultHint)
    }

    /// Whether a panel is showing the answer, which is the one case the strip
    /// stays out of. Only `.needsScreenContext` is excluded: that panel explains a
    /// missing session rather than showing a result, and the banner labels it.
    ///
    /// The same question `KeyboardController.bannerOptions` asks, spelled once
    /// here so the list and the state cannot disagree about who owns the answer.
    static func resultPanelIsOpen(_ overlay: KeyboardOverlay) -> Bool {
        guard case .aiResult(let kind) = overlay else { return false }
        return kind != .needsScreenContext
    }

    private var surface: Color {
        switch state {
        case .hint: return Theme.Keys.panel.opacity(0.5)
        default: return Theme.Keys.panel
        }
    }

    // MARK: The tag on the left

    @ViewBuilder
    private var leading: some View {
        switch state {
        case .hint:
            EmptyView()
        case .context:
            tag(AIAction.reply.icon, "On screen", tint: Theme.Keys.secondaryLabel)
        case .working(let action), .options(let action, _, _):
            tag(action.icon, action.title, tint: Theme.Brand.solid)
        case .failed(let action, _, _):
            tag("exclamationmark.triangle", action.title, tint: Theme.Semantic.warning)
        case .needsSetup:
            tag("exclamationmark.triangle", AIAction.reply.title, tint: Theme.Semantic.warning)
        case .dictating(_, let isListening):
            tag("mic", isListening ? "Recording" : "Transcribing", tint: Theme.Semantic.record)
        case .dictationFailed:
            tag("mic.slash", "Dictation", tint: Theme.Semantic.warning)
        }
    }

    /// The action's name, always in words beside its glyph.
    ///
    /// A glyph alone would repeat the mistake the one-tap rewrite button already
    /// made twice: `sparkle` and `sparkles` are one drawing at two counts, and
    /// `figure.wave` in a keyboard reads as a contacts button. Whatever the banner
    /// is doing, it says so.
    private func tag(_ icon: String, _ title: String, tint: Color) -> some View {
        VStack(spacing: 1) {
            Image(systemName: icon)
                .font(Theme.Glyph.medium(13))
            Text(title.uppercased())
                .font(.system(size: 8, weight: .semibold))
                .tracking(0.4)
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .frame(width: 52)
        .accessibilityHidden(true)
    }

    // MARK: The middle

    @ViewBuilder
    private var content: some View {
        switch state {
        case .hint(let text):
            caption(text)

        case .context(let sender, let message, let language):
            VStack(alignment: .leading, spacing: 0) {
                Text(sender)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.Keys.secondaryLabel)
                answer(message, language: language, size: 13)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("From \(sender): \(message)")

        case .working(let action):
            // The same shimmer the panel used, at one line. The phase is driven by
            // `beginWork`'s own animation task, so it stops when the call does
            // rather than on a timer of its own.
            VStack(alignment: .leading, spacing: 4) {
                ShimmerLine(width: nil, phase: controller.workingPhase)
                ShimmerLine(
                    width: 120,
                    phase: (controller.workingPhase + 0.18).truncatingRemainder(dividingBy: 1))
            }
            .accessibilityLabel("\(action.title), working")

        case .options(_, let options, let index):
            let option = options[index]
            VStack(alignment: .leading, spacing: 1) {
                if !option.label.isEmpty {
                    Text(option.label.uppercased())
                        .font(.system(size: 8, weight: .semibold))
                        .tracking(0.4)
                        .foregroundStyle(Theme.Brand.solid)
                        .lineLimit(1)
                }
                answer(option.text, language: option.language, size: 14)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                options.count > 1
                    ? "\(option.label). \(option.text). Option \(index + 1) of \(options.count)"
                    : "\(option.label). \(option.text)")

        case .failed(_, let title, let detail):
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.Keys.label)
                    .lineLimit(1)
                caption(detail)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title). \(detail)")

        case .needsSetup:
            caption(
                "Reply answers the message in front of you. Tap Set up to start screen context.")

        case .dictating(let transcript, let isListening):
            if transcript.isEmpty {
                WaveformView(
                    phase: controller.waveformPhase,
                    barCount: 26,
                    color: Theme.Semantic.record.opacity(0.85),
                    isActive: isListening
                )
                .frame(height: 22)
                .accessibilityLabel(isListening ? "Recording" : "Transcribing")
            } else {
                answer(transcript, language: controller.language, size: 14)
                    .accessibilityLabel("Transcript: \(transcript)")
            }

        case .dictationFailed(let reason):
            VStack(alignment: .leading, spacing: 0) {
                Text("Nothing to insert")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.Keys.label)
                    .lineLimit(1)
                caption(reason)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Nothing to insert. \(reason)")
            .accessibilityIdentifier("banner-dictation-failed")
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(Theme.Keys.secondaryLabel)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Generated text, laid out in the language it is written in.
    ///
    /// The one thing in this strip that follows a direction, and it follows the
    /// *answer's* rather than the keyboard's: a Hebrew reply stays Hebrew while
    /// the user is typing English into the field underneath.
    private func answer(_ text: String, language: KeyboardLanguage, size: CGFloat) -> some View {
        Text(text)
            .font(.system(size: size))
            .foregroundStyle(Theme.Keys.label)
            .lineLimit(1)
            // **Shrink before truncating, because the user is being asked to accept
            // this.** One line is all a 48pt strip has — the height is capped by
            // the frame fingerprint, see `Theme.Metrics.bannerHeight` — and a reply
            // whose end is an ellipsis is one the user inserts without having read
            // it. Scaling buys about six more words before that happens. Past that
            // it still truncates, and the honest mitigation is that Use puts the
            // whole sentence in the field, where it is editable and where they were
            // going to read it before sending anyway.
            .minimumScaleFactor(0.85)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: language.isRightToLeft ? .trailing : .leading)
            .environment(\.layoutDirection, language.layoutDirection)
    }

    // MARK: The button on the right

    @ViewBuilder
    private var trailing: some View {
        switch state {
        case .hint, .context, .working:
            EmptyView()

        case .options(_, let options, let index):
            HStack(spacing: Theme.Space.xxs) {
                if options.count > 1 { pager(count: options.count, index: index) }
                button("Use", tint: Theme.Brand.gradient, filled: true) {
                    controller.useBannerOption()
                }
                .accessibilityIdentifier("banner-use")
            }

        case .failed:
            button("Dismiss", tint: nil, filled: false) { controller.clearBanner() }
                .accessibilityIdentifier("banner-dismiss")

        case .needsSetup:
            button("Set up", tint: Theme.Brand.gradient, filled: true) {
                controller.show(.aiResult(.needsScreenContext))
            }
            .accessibilityIdentifier("banner-setup")

        case .dictating(_, let isListening):
            button(
                isListening ? "Stop" : "Cancel",
                tint: LinearGradient(
                    colors: [Theme.Semantic.record, Theme.Semantic.record],
                    startPoint: .top, endPoint: .bottom),
                filled: true
            ) {
                controller.stopDictation(insert: isListening)
            }
            .accessibilityIdentifier("banner-stop")

        case .dictationFailed:
            // `stopDictation(insert: false)` rather than `clearBanner`: the reason
            // lives on the session, not on the banner, so clearing this side of it
            // would leave the sentence to reappear on the next tick.
            button("Dismiss", tint: nil, filled: false) {
                controller.stopDictation(insert: false)
            }
            .accessibilityIdentifier("banner-dictation-dismiss")
        }
    }

    /// Which of the answers is showing. Tappable as well as swipeable, because a
    /// swipe on a 56pt strip sitting directly above the keys competes with the
    /// scroll of whatever the host app is showing, and because a dot is the only
    /// part of this a VoiceOver user can address.
    private func pager(count: Int, index: Int) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<count, id: \.self) { slot in
                Button {
                    controller.showBannerOption(slot)
                } label: {
                    Circle()
                        .fill(
                            slot == index
                                ? Theme.Brand.solid : Theme.Keys.secondaryLabel.opacity(0.35)
                        )
                        .frame(width: 6, height: 6)
                        .frame(width: 16, height: 28)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Option \(slot + 1) of \(count)")
                .accessibilityAddTraits(slot == index ? [.isSelected] : [])
            }
        }
        .accessibilityIdentifier("banner-pager")
    }

    /// `LinearGradient?` rather than a generic `ShapeStyle`, because the one
    /// unfilled caller passes `nil` and a generic parameter cannot be inferred
    /// from it. Every filled caller has a gradient to hand anyway: the brand one,
    /// or the flat record red spelled as a gradient of itself.
    private func button(
        _ title: String, tint: LinearGradient?, filled: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(filled ? Theme.Text.onBrand : Theme.Keys.label)
                .lineLimit(1)
                .padding(.horizontal, Theme.Space.sm)
                .frame(height: 32)
                .background {
                    let shape = RoundedRectangle(
                        cornerRadius: Theme.Radius.chip, style: .continuous)
                    if filled, let tint {
                        shape.fill(tint)
                    } else {
                        shape.fill(Theme.Keys.card)
                    }
                }
                .contentShape(Rectangle())
        }
        .pressable()
    }
}
