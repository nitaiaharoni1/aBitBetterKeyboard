import SwiftUI
import AIKeyboardCore

struct PlaygroundView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("playgroundTourProgress") private var tourProgress = 0
    @ObservedObject private var screenContext = ScreenContextSession.shared
    @StateObject private var target: MockTextTarget
    @StateObject private var controller: KeyboardController

    @State private var messages: [PlaygroundMessage] = []
    @State private var pendingAICompletion: PlaygroundTourStep?
    @State private var delayedAdvance: Task<Void, Never>?
    @State private var originalScreenContextAllowed: Bool

    init() {
        let progress = UserDefaults.standard.integer(forKey: "playgroundTourProgress")
        let seed = PlaygroundTourStep(rawValue: progress)?.seedText ?? ""
        let document = MockTextTarget(text: seed)
        _target = StateObject(wrappedValue: document)
        _controller = StateObject(
            wrappedValue: KeyboardController(target: document, language: .english)
        )
        _originalScreenContextAllowed = State(
            initialValue: SharedStore.shared.screenContextAllowed
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                PlaygroundTourCard(step: currentStep, onSkip: skipTask)
                conversation
                composer
                KeyboardView(controller: controller)
            }
            .background(Theme.Surface.background)
            // Presented sheets carry the house depth token. The iPhone sheet
            // fills the window and clips it away; it reads where the sheet
            // floats, as on iPad.
            .ambientDepth()
            .navigationTitle("Playground")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset Tour", action: resetTour)
                        .font(Theme.Fonts.body.weight(.semibold))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(Theme.Fonts.body.weight(.semibold))
                }
            }
            .onAppear(perform: prepareReplyDemoIfNeeded)
            .onDisappear {
                delayedAdvance?.cancel()
                if screenContext.source == .scripted {
                    screenContext.stop()
                }
                restoreScreenContextPreference()
            }
            // **`onDisappear` is not the last word on a persisted setting.** The
            // reply task switches `screenContextAllowed` on so the keyboard will
            // offer Reply against the scripted session, and puts it back when the
            // task ends or the sheet closes. Neither of those runs if iOS kills
            // the app while this step is on screen, and what is left behind is a
            // stored yes to screen context from somebody who only came to look at
            // the playground. Backgrounding is the last moment guaranteed to run,
            // so the flag goes back there and comes back on return.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    prepareReplyDemoIfNeeded()
                } else {
                    restoreScreenContextPreference()
                }
            }
            .onChange(of: controller.lastInteraction) { _, interaction in
                handle(interaction)
            }
            .onChange(of: controller.runningAction) { _, action in
                guard action == currentStep?.expectedAIAction else { return }
                pendingAICompletion = currentStep
            }
            .onChange(of: controller.isWorking) { wasWorking, isWorking in
                guard wasWorking, !isWorking, pendingAICompletion == currentStep else { return }
                pendingAICompletion = nil
                advance(after: .milliseconds(500))
            }
            .onChange(of: controller.block) { _, block in
                guard let block, block.action == currentStep?.expectedAIAction else { return }
                advance(after: .milliseconds(900))
            }
        }
    }

    private var currentStep: PlaygroundTourStep? {
        PlaygroundTourStep(rawValue: tourProgress)
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .trailing, spacing: Theme.Space.xs) {
                    if messages.isEmpty {
                        Text("Messages you send will appear here.")
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.Text.tertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, Theme.Space.lg)
                    }

                    ForEach(messages) { message in
                        Text(message.text)
                            .font(Theme.Fonts.body)
                            .foregroundStyle(Theme.Text.onBrand)
                            .padding(.horizontal, Theme.Space.sm)
                            .padding(.vertical, Theme.Space.xs)
                            .background(Theme.Brand.action)
                            .clipShape(
                                UnevenRoundedRectangle(
                                    topLeadingRadius: Theme.Radius.card,
                                    bottomLeadingRadius: Theme.Radius.card,
                                    bottomTrailingRadius: 4,
                                    topTrailingRadius: Theme.Radius.card,
                                    style: .continuous
                                )
                            )
                            .frame(maxWidth: 290, alignment: .trailing)
                            .id(message.id)
                            .accessibilityLabel("Sent message: \(message.text)")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(Theme.Space.sm)
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: messages.count) { _, _ in
                guard let last = messages.last else { return }
                withAnimation(Theme.Motion.content) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
        .frame(maxHeight: .infinity)
        .scrollDismissesKeyboard(.never)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: Theme.Space.xs) {
            Text(target.text.isEmpty ? PlaygroundView.seedPlaceholder : target.text)
                .font(Theme.Fonts.body)
                .foregroundStyle(target.text.isEmpty ? Theme.Text.tertiary : Theme.Text.primary)
                .lineLimit(1...4)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .environment(\.layoutDirection, controller.hostLanguage.layoutDirection)
                .padding(.horizontal, Theme.Space.sm)
                .padding(.vertical, Theme.Space.xs)
                .background(Theme.Surface.raised)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Theme.Surface.separator, lineWidth: 1)
                }
                .accessibilityLabel("Message")
                .accessibilityValue(target.text)

            Button(action: sendMessage) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.Text.onBrand)
                    .frame(width: 44, height: 44)
                    .background(Theme.Brand.action)
                    .clipShape(Circle())
            }
            .disabled(trimmedMessage.isEmpty)
            .opacity(trimmedMessage.isEmpty ? 0.45 : 1)
            .accessibilityLabel("Send message")
            .accessibilityIdentifier("playground-send")
        }
        .padding(.horizontal, Theme.Space.sm)
        .padding(.vertical, Theme.Space.xs)
        .background(Theme.Surface.background)
    }

    private var trimmedMessage: String {
        target.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sendMessage() {
        let text = trimmedMessage
        guard !text.isEmpty else { return }
        messages.append(PlaygroundMessage(text: text))
        target.text = ""
        controller.refreshSuggestions()
        if currentStep == .send {
            advance(after: .milliseconds(250))
        }
    }

    private func handle(_ interaction: KeyboardInteraction?) {
        guard let kind = interaction?.kind else { return }
        switch (currentStep, kind) {
        case (.suggestion, .suggestion), (.emoji, .emoji), (.languageSwitch, .languageSwitch):
            advance(after: .milliseconds(350))
        case (.dictation, .dictation):
            advance(after: .milliseconds(1800))
        default:
            break
        }
    }

    private func skipTask() {
        advance(after: .zero)
    }

    private func advance(after delay: Duration) {
        delayedAdvance?.cancel()
        delayedAdvance = Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            moveToNextTask()
        }
    }

    private func moveToNextTask() {
        guard let currentStep else { return }
        pendingAICompletion = nil
        if currentStep == .reply, screenContext.source == .scripted {
            screenContext.stop()
        }
        if currentStep == .reply {
            restoreScreenContextPreference()
        }
        controller.dismissOverlay()
        let next = currentStep.next
        tourProgress = next?.rawValue ?? PlaygroundTourStep.allCases.count
        target.text = next?.seedText ?? ""
        controller.refreshSuggestions()
        prepareReplyDemoIfNeeded()
    }

    private func resetTour() {
        delayedAdvance?.cancel()
        pendingAICompletion = nil
        messages.removeAll()
        if screenContext.source == .scripted {
            screenContext.stop()
        }
        restoreScreenContextPreference()
        controller.dismissOverlay()
        controller.language = .english
        tourProgress = PlaygroundTourStep.fix.rawValue
        target.text = PlaygroundTourStep.fix.seedText
        controller.refreshSuggestions()
    }

    private func prepareReplyDemoIfNeeded() {
        guard currentStep == .reply else { return }
        SharedStore.shared.screenContextAllowed = true
        if screenContext.source != .capture {
            screenContext.start()
        }
    }

    private func restoreScreenContextPreference() {
        SharedStore.shared.screenContextAllowed = originalScreenContextAllowed
    }

    /// Shared with onboarding's last step so the two places that hand the user a
    /// keyboard hand them the same sentence and the same next move.
    ///
    /// **Both name the button rather than drawing it.** These said "tap ✨" above a
    /// bar carrying two brand-tinted buttons side by side, the left one wearing the
    /// default tone's own icon — which was SF `sparkle`, the same drawing as the
    /// menu's `sparkles`. `ToneSetting.settingsNote` fixed exactly this in Settings
    /// and these two were left behind; the name now comes from
    /// `SuggestionBar.aiButtonName`, so there is one spelling of it.
    static let seedSentence = "i dont think we should do it because its not make sense"
    static let seedPlaceholder =
        "Type in Hebrew or English, then use \(SuggestionBar.aiButtonName)"
    /// **One tap, not two, and the actions are named because they are on screen
    /// now.** This used to say "tap ✨, then Fix", which was the panel flow: the
    /// sparkle opened a menu and Fix was a row inside it. Fix and Rewrite are keys
    /// in the action row, so the instruction that matches what the user is looking
    /// at is the name of the key.
    static let seedHint =
        "This sentence has mistakes in it on purpose. Tap Fix in \(SuggestionBar.aiButtonName) to "
        + "correct it, or Rewrite to say it another way."
}

private struct PlaygroundMessage: Identifiable {
    let id = UUID()
    let text: String
}
