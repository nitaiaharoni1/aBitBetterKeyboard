import SwiftUI

// MARK: - Shared chrome

/// Header shared by every panel that covers the key grid. Keeping the escape
/// route in one place means the user can always get back to typing in one tap.
struct PanelHeader: View {
    let title: String
    var subtitle: String?
    var onBack: (() -> Void)?
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.backward")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.Keys.secondaryLabel)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .pressable()
                .accessibilityLabel("Back")
            }

            SparkleMark(size: 14)

            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.Keys.label)

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Keys.secondaryLabel)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: Theme.Space.xs)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Keys.secondaryLabel)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Theme.Keys.function.opacity(0.6)))
                    .contentShape(Circle())
            }
            .pressable()
            .accessibilityLabel("Close and go back to the keyboard")
        }
        .padding(.horizontal, Theme.Space.sm)
        .frame(height: 38)
    }
}

/// Background treatment every panel sits on.
struct PanelSurface<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.Keys.panel)
    }
}

// MARK: - The four actions

public struct AIMenuPanel: View {
    @ObservedObject var controller: KeyboardController

    private let columns = [
        GridItem(.flexible(), spacing: Theme.Space.xs),
        GridItem(.flexible(), spacing: Theme.Space.xs)
    ]

    public init(controller: KeyboardController) {
        self.controller = controller
    }

    public var body: some View {
        PanelSurface {
            VStack(spacing: 0) {
                PanelHeader(
                    title: "AI",
                    subtitle: controller.aiTargetText.isEmpty ? nil : controller.aiTargetText,
                    onClose: { controller.dismissOverlay() }
                )

                LazyVGrid(columns: columns, spacing: Theme.Space.xs) {
                    ForEach(AIAction.allCases) { action in
                        actionCard(action)
                    }
                }
                .padding(.horizontal, Theme.Space.sm)
                .padding(.bottom, Theme.Space.sm)
            }
        }
    }

    private func actionCard(_ action: AIAction) -> some View {
        let isAvailable = Self.isAvailable(action, hasTextToWorkWith: controller.hasTextToWorkWith)

        return Button {
            controller.run(action)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: action.icon)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Theme.Brand.gradient)

                    // Reply is the only action whose availability changes minute
                    // to minute, so it is the only one that reports its state.
                    if action.needsScreenContext && controller.canReply {
                        Circle()
                            .fill(Theme.Semantic.record)
                            .frame(width: 6, height: 6)
                    }
                }
                .frame(height: 22)

                Text(action.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Keys.label)

                Text(subtitle(for: action))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Keys.secondaryLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Space.sm)
            .padding(.vertical, Theme.Space.xs)
            .frame(height: 74)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Theme.Keys.card)
            )
            .opacity(isAvailable ? 1 : 0.5)
            .contentShape(Rectangle())
        }
        .pressable()
        .disabled(!isAvailable)
        .accessibilityIdentifier("ai-action-\(action.rawValue)")
        .accessibilityLabel("\(action.title). \(subtitle(for: action))")
    }

    /// Reply stays tappable without a session so it can explain itself; the text
    /// actions genuinely have nothing to do without text.
    ///
    /// Static and taking its input rather than reading `controller`, so the bar
    /// that opens this panel can ask the same question — see `hasRunnableAction`.
    static func isAvailable(_ action: AIAction, hasTextToWorkWith: Bool) -> Bool {
        action.needsScreenContext ? true : hasTextToWorkWith
    }

    /// Whether opening this panel would put anything tappable in front of the
    /// user.
    ///
    /// **`SuggestionBar` reads this instead of deciding for itself, and the two
    /// disagreeing was D8's defect.** The bar's sparkle was enabled by
    /// `hasTextToWorkWith || canReply`, which is false on an empty field with no
    /// session — exactly the state the Reply panel exists for. So: open WhatsApp,
    /// tap the compose box, tap the AI button to answer the message on screen, and
    /// nothing happened, under a hint reading "Type something first", while the
    /// panel one tap away held the broadcast picker and the explanation of how to
    /// start a session. Reply is always available here, so this is always true;
    /// it is written as a question over the actions rather than as `true` so that
    /// a future action list cannot make it a lie without failing
    /// `SparkleReachabilityTests`.
    static func hasRunnableAction(hasTextToWorkWith: Bool) -> Bool {
        AIAction.allCases.contains { isAvailable($0, hasTextToWorkWith: hasTextToWorkWith) }
    }

    /// Reply's subtitle names the sender rather than the app, because the app is
    /// the one thing this design cannot know: see `ScreenContextStrip`.
    ///
    /// The last line used to promise a read unconditionally. It is the same
    /// promise the strip makes and it fails the same way: reading inside the
    /// capture process is not built, so a tap raises the request and nothing
    /// answers. Once that has happened, this says so.
    private func subtitle(for action: AIAction) -> String {
        guard action.needsScreenContext else { return action.subtitle }
        switch controller.screenContext {
        case _ where !controller.canReply: return "Needs screen context"
        case .ready(let context): return "To \(context.sender)"
        // Not "got no answer" any more: the flag now also covers a read that was
        // answered, with a failure about the setup rather than about this screen.
        // See `ScreenContextSession.lastReadWentUnanswered`.
        case _ where controller.screenReadWentUnanswered: return "The last read didn't work"
        default: return "Reads the screen when you tap"
        }
    }
}

// MARK: - Results

public struct AIResultPanel: View {
    @ObservedObject var controller: KeyboardController
    let kind: AIActionResultKind

    public init(controller: KeyboardController, kind: AIActionResultKind) {
        self.controller = controller
        self.kind = kind
    }

    public var body: some View {
        PanelSurface {
            VStack(spacing: 0) {
                PanelHeader(
                    title: title,
                    onBack: { controller.show(.aiMenu) },
                    onClose: { controller.dismissOverlay() }
                )

                if controller.isWorking {
                    loading
                } else if let error = controller.aiError {
                    // The tone chips are navigation, not a result: after a failed
                    // call the user still needs them to try a different register.
                    if case .variants = kind { toneChips }
                    failure(error)
                } else {
                    if controller.aiProvenance?.isBestEffort == true {
                        bestEffortNotice
                    }
                    switch kind {
                    case .fix:
                        fixResult
                    case .variants:
                        variantResults
                    case .replies:
                        replyResults
                    case .needsScreenContext:
                        screenContextPrompt
                    }
                }
            }
        }
    }

    private var title: String {
        switch kind {
        case .fix: return "Fix"
        // The overlay carries a `ToneStyle`, which for a custom tone is the
        // built-in the answer is labelled with — right for tagging the variant,
        // wrong for naming the register the user asked for.
        case .variants(let tone):
            if controller.selectedToneIsCustom { return ToneSetting.customTitle }
            return tone?.title ?? "Rewrite"
        case .replies: return "Reply"
        case .needsScreenContext: return "Reply"
        }
    }

    // MARK: Loading

    private var loading: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            ForEach(0..<3, id: \.self) { index in
                ShimmerLine(
                    width: [nil, 220, 160][index],
                    phase: (controller.workingPhase + Double(index) * 0.18)
                        .truncatingRemainder(dividingBy: 1)
                )
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.md)
        .padding(.top, Theme.Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("Working")
    }

    // MARK: Failure

    /// Every AI action can come back with nothing, and each reason has a
    /// different thing the user can do about it. Showing the reason is the
    /// difference between a keyboard that looks broken and one that looks honest.
    private func failure(_ error: AIEngineError) -> some View {
        VStack(spacing: Theme.Space.xs) {
            Spacer(minLength: 0)
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Theme.Keys.secondaryLabel)
            Text(error.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.Keys.label)
            Text(error.message)
                .font(.system(size: 13))
                .foregroundStyle(Theme.Keys.secondaryLabel)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            secondaryButton("Close") { controller.dismissOverlay() }
                .padding(.horizontal, Theme.Space.sm)
                .padding(.bottom, Theme.Space.sm)
        }
        .padding(.horizontal, Theme.Space.md)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(error.title). \(error.message)")
    }

    /// Shown when the on-device model answered in a language Apple does not list
    /// as supported, because no cloud engine was reachable. The result is still
    /// worth offering — the user can see their original right above it — but it
    /// must not be presented with the same confidence as a supported language.
    private var bestEffortNotice: some View {
        HStack(spacing: 5) {
            Image(systemName: "info.circle")
                .font(.system(size: 10, weight: .medium))
            Text("Best effort — this language isn't fully supported on device")
                .font(.system(size: 11))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Theme.Keys.secondaryLabel)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Space.sm)
        .padding(.bottom, 2)
    }

    // MARK: Fix

    private var fixResult: some View {
        VStack(spacing: Theme.Space.xs) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(controller.aiSourceText)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Keys.secondaryLabel)
                        .strikethrough(true, color: Theme.Keys.secondaryLabel.opacity(0.5))

                    Divider().overlay(Theme.Keys.secondaryLabel.opacity(0.2))

                    Text(controller.aiResultText)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.Keys.label)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Space.sm)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .fill(Theme.Keys.card)
                )
            }
            .padding(.horizontal, Theme.Space.sm)

            HStack(spacing: Theme.Space.xs) {
                secondaryButton("Keep original") { controller.dismissOverlay() }
                primaryButton("Replace") { controller.applyResult(controller.aiResultText) }
            }
            .padding(.horizontal, Theme.Space.sm)
            .padding(.bottom, Theme.Space.sm)
        }
    }

    // MARK: Rewrite and tone

    private var variantResults: some View {
        VStack(spacing: Theme.Space.xs) {
            toneChips

            ScrollView {
                VStack(spacing: Theme.Space.xs) {
                    if controller.variants.isEmpty {
                        Text("Pick a tone")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.Keys.secondaryLabel)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, Theme.Space.xs)
                    }

                    ForEach(controller.variants) { variant in
                        variantCard(variant)
                    }
                }
                .padding(.bottom, Theme.Space.sm)
            }
            .padding(.horizontal, Theme.Space.sm)
        }
    }

    private var toneChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Space.xxs) {
                // The user's own tone leads, and only appears when they have
                // written one. `ToneStyle` cannot carry it as a seventh case — its
                // raw values are the persisted setting — so it is a chip of its
                // own rather than a member of `allCases`. See `ToneSetting`.
                if let custom = controller.customTone {
                    chip(
                        title: custom.title,
                        icon: custom.icon,
                        isSelected: controller.selectedToneIsCustom
                    ) {
                        controller.selectTone(custom)
                    }
                }

                // A custom tone runs as one of the six on the engines that cannot
                // take free text, so the built-in chips have to check that it is
                // not the one running or they light up as if they had been picked.
                ForEach(ToneStyle.allCases) { tone in
                    let isSelected = controller.selectedTone == tone && !controller.selectedToneIsCustom
                    chip(title: tone.title, icon: tone.icon, isSelected: isSelected) {
                        controller.selectTone(tone)
                    }
                }
            }
            .padding(.horizontal, Theme.Space.sm)
            .padding(.vertical, 2)
        }
        .frame(height: 38)
    }

    /// One chip. Extracted only because there are now two kinds of them and the
    /// body was duplicated.
    private func chip(
        title: String, icon: String, isSelected: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(isSelected ? Theme.Text.onBrand : Theme.Keys.label)
            .padding(.horizontal, Theme.Space.sm)
            .padding(.vertical, 7)
            .background {
                if isSelected {
                    Capsule().fill(Theme.Brand.gradient)
                } else {
                    Capsule().fill(Theme.Keys.card)
                }
            }
            .contentShape(Capsule())
        }
        .pressable()
    }

    private func variantCard(_ variant: RewriteVariant) -> some View {
        Button {
            controller.applyResult(variant.text)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Image(systemName: variant.tone.icon)
                        .font(.system(size: 10, weight: .semibold))
                    // Rewrite labels the decision each version takes; Tone has
                    // only the register, which is already the card's title.
                    Text((variant.label ?? variant.tone.title).uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.6)
                }
                .foregroundStyle(Theme.Brand.solid)

                Text(variant.text)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.Keys.label)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Space.sm)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Theme.Keys.card)
            )
            .contentShape(Rectangle())
        }
        .pressable()
        .accessibilityLabel("\(variant.label ?? variant.tone.title): \(variant.text)")
        .accessibilityHint("Replaces your text")
    }

    // MARK: Replies

    private var replyResults: some View {
        VStack(spacing: Theme.Space.xs) {
            // Restate what is being answered, and restate the reading the reply
            // was actually written about rather than whatever the strip is
            // showing now: the screen can move on while the model is generating,
            // and then those are two different messages. No app name — the same
            // reason the strip does not name one.
            if let context = controller.replyContext ?? controller.screenContext.context {
                HStack(spacing: 5) {
                    Text(context.sender)
                        .font(.system(size: 11, weight: .semibold))
                    Text(context.message)
                        .font(.system(size: 11))
                        .lineLimit(1)
                }
                .foregroundStyle(Theme.Keys.secondaryLabel)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Space.sm)
                .environment(\.layoutDirection, context.language.layoutDirection)
            }

            ScrollView {
                VStack(spacing: Theme.Space.xs) {
                    ForEach(controller.replies) { reply in
                        replyCard(reply, language: controller.screenContext.context?.language ?? .english)
                    }
                }
                .padding(.bottom, Theme.Space.sm)
            }
            .padding(.horizontal, Theme.Space.sm)
        }
    }

    /// The whole card flips for a Hebrew reply, so the intent label sits on the
    /// same edge the sentence starts on.
    private func replyCard(_ reply: ReplyOption, language: KeyboardLanguage) -> some View {
        Button {
            controller.applyResult(reply.text)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Image(systemName: reply.icon)
                        .font(.system(size: 10, weight: .semibold))
                    Text(reply.intent.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.6)
                }
                .foregroundStyle(Theme.Brand.solid)

                Text(reply.text)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.Keys.label)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Space.sm)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Theme.Keys.card)
            )
            .contentShape(Rectangle())
        }
        .pressable()
        .environment(\.layoutDirection, language.layoutDirection)
        .accessibilityLabel("\(reply.intent): \(reply.text)")
        .accessibilityHint("Inserts this reply")
    }

    /// Reply tapped with no live session, and the one place in the keyboard where
    /// a session can be started.
    ///
    /// **This is where the entry point has to be, because the strip cannot hold
    /// it.** `ScreenContextStrip` is not rendered at all while screen context is
    /// off, so an affordance that lived only there could start nothing; the strip
    /// carries the restart for an *ended* session and this carries the first start.
    ///
    /// **The button used to be absent on purpose, and the reason turned out to be
    /// half right.** Only iOS can start a broadcast, which is still true — but the
    /// inference that the picker therefore belongs in the app does not follow.
    /// `RPSystemBroadcastPickerView` is a `UIView` whose button talks to `replayd`
    /// over XPC and touches no `UIApplication`; `BroadcastPickerButton`'s doc
    /// comment carries the disassembly. What that does not prove is that `replayd`
    /// answers a keyboard extension, so the words that send the user to the app
    /// stay underneath the button rather than being replaced by it.
    ///
    /// **It reads the recorded state, not just whether the container is
    /// reachable.** The first version of this branched on `CaptureChannel.isReachable`
    /// alone and never looked at `controller.screenContext`, so after a session
    /// ended `.notConfigured` this panel still said "Screen context is off" and
    /// still offered the picker — while the strip, three points above it, printed
    /// the reason and correctly withheld the button. Two surfaces reading one page
    /// and disagreeing about it is the bug `ScreenContextEndReason.recovery` was
    /// added to prevent, and this was the same bug one layer up: the picker there
    /// would have looped the user through the same one-second broadcast for as
    /// long as they kept tapping.
    private var screenContextPrompt: some View {
        VStack(spacing: Theme.Space.sm) {
            VStack(spacing: 4) {
                Text(prompt.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Keys.label)

                Text(prompt.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Keys.secondaryLabel)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Theme.Space.md)

            if prompt.offersPicker {
                BroadcastPickerButton(width: 52, height: 52)
                    .frame(width: 52, height: 52)
                    // White first, brand tint over it: the system draws the glyph
                    // black. See `BroadcastPickerButton`.
                    .background(
                        Circle()
                            .fill(Theme.Text.onBrand)
                            .overlay(Circle().fill(Theme.Brand.softGradient))
                    )
                    .accessibilityLabel("Start screen context")
                    .accessibilityHint("Opens the iOS screen broadcast picker")
                    .accessibilityIdentifier("ai-start-broadcast")

                Text(
                    "If nothing opens, do it from AI Keyboard › Screen Context. iOS shows a red indicator for as long as it runs."
                )
                .font(.system(size: 11))
                .foregroundStyle(Theme.Keys.secondaryLabel)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.Space.md)
            }

            Spacer(minLength: 0)
        }
        .padding(.top, Theme.Space.xs)
    }

    /// The ending on the page, if the last thing that happened was one. `.off` is
    /// not an ending: it is the ordinary state of a phone that has never started a
    /// broadcast, and it has no reason to print.
    private var endedReason: ScreenContextEndReason? {
        guard case .ended(let reason) = controller.screenContext else { return nil }
        return reason
    }

    /// The two measurements this panel makes, read at render time.
    ///
    /// `CaptureChannel.isReachable` is whether this process can reach the App Group
    /// at all — false in the keyboard until Full Access is granted, and the
    /// difference between "screen context is off" and "screen context cannot work
    /// here". `BackendTransport.configured()` is whether there is anywhere to send
    /// a screen once one has been captured. Everything decided from them is in
    /// `ScreenContextPrompt`, where a test can reach it.
    private var prompt: ScreenContextPrompt {
        ScreenContextPrompt(
            canReachChannel: CaptureChannel.isReachable,
            cloudConfigured: BackendTransport.configured() != nil,
            ended: endedReason)
    }

    // MARK: Buttons

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.Text.onBrand)
                .frame(maxWidth: .infinity)
                .frame(height: Theme.Metrics.minTouchTarget)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                        .fill(Theme.Brand.gradient)
                )
                .contentShape(Rectangle())
        }
        .pressable()
    }

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.Keys.label)
                .frame(maxWidth: .infinity)
                .frame(height: Theme.Metrics.minTouchTarget)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                        .fill(Theme.Keys.card)
                )
                .contentShape(Rectangle())
        }
        .pressable()
    }
}

// MARK: - Reply with no session behind it

/// What the Reply panel says when there is nothing to reply to, and whether it
/// offers to start a broadcast.
///
/// A value type rather than three computed properties on the view, because the
/// decision is pure and the one thing worth pinning is not renderable: **the
/// picker must be offered only when a broadcast started now could get further
/// than the last one did.** It shipped asking two of the three questions.
/// `SampleHandler.broadcastStarted` refuses a session outright when
/// `ScreenReadService.canRead` is false, so with no cloud model the keyboard was
/// putting a real screen recording in front of the user — countdown, system
/// recording indicator and all — that iOS would end inside a second. That is the
/// same trap `ScreenContextView` reordered its own sections to avoid, one process
/// away.
///
/// The three refusals are deliberately distinct sentences. "Turn on Full Access"
/// and "set up a cloud model" are different work, in different places, and an
/// ending a restart cannot fix is a fourth thing again.
struct ScreenContextPrompt: Equatable {
    let title: String
    let detail: String
    let offersPicker: Bool

    init(canReachChannel: Bool, cloudConfigured: Bool, ended: ScreenContextEndReason?) {
        // The keyboard reads what the capture process writes through the App
        // Group, and iOS hands a keyboard extension that container only once Full
        // Access is granted. Starting a broadcast from here would run a capture
        // this keyboard could never read.
        guard canReachChannel else {
            title = "Screen context needs Full Access"
            detail =
                "This keyboard cannot reach AI Keyboard's shared storage, so it could not read a screen even while one is being captured. Turn on Full Access for AI Keyboard in Settings, under General › Keyboard › Keyboards."
            offersPicker = false
            return
        }
        // The same two strings the strip prints, off the same reason.
        if let ended, !ended.canRestart {
            title = "Screen context can't run yet"
            detail = "\(ended.explanation) \(ended.recovery)"
            offersPicker = false
            return
        }
        // The same wall as the one above, reached before the broadcast instead of
        // one second after it.
        guard cloudConfigured else {
            title = "Screen context can't run yet"
            detail =
                "Reading a screen needs a cloud model, and none is set up. \(BackendTransport.setUpRecovery)"
            offersPicker = false
            return
        }
        title = "Screen context is off"
        detail =
            "Reply answers the message in front of you. Tap below and iOS shows its own list of what can record the screen — pick AI Keyboard, then Start Broadcast."
        offersPicker = true
    }
}
