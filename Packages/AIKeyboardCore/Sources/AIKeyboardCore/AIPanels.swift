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
        let isAvailable = self.isAvailable(action)

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
    private func isAvailable(_ action: AIAction) -> Bool {
        action.needsScreenContext ? true : controller.hasTextToWorkWith
    }

    private func subtitle(for action: AIAction) -> String {
        guard action.needsScreenContext else { return action.subtitle }
        switch controller.screenContext {
        case _ where !controller.canReply: return "Needs screen context"
        case .ready(let context): return "From \(context.appName)"
        default: return action.subtitle
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
                } else {
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
        case .variants(let tone): return tone?.title ?? "Rewrite"
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
                ForEach(ToneStyle.allCases) { tone in
                    let isSelected = controller.selectedTone == tone
                    Button {
                        controller.selectTone(tone)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: tone.icon)
                                .font(.system(size: 11, weight: .medium))
                            Text(tone.title)
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
            }
            .padding(.horizontal, Theme.Space.sm)
            .padding(.vertical, 2)
        }
        .frame(height: 38)
    }

    private func variantCard(_ variant: RewriteVariant) -> some View {
        Button {
            controller.applyResult(variant.text)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Image(systemName: variant.tone.icon)
                        .font(.system(size: 10, weight: .semibold))
                    Text(variant.tone.title.uppercased())
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
        .accessibilityLabel("\(variant.tone.title): \(variant.text)")
        .accessibilityHint("Replaces your text")
    }

    // MARK: Replies

    private var replyResults: some View {
        VStack(spacing: Theme.Space.xs) {
            if let context = controller.screenContext.context {
                // Restate what is being answered. A reply generated from
                // something the user cannot see is a reply they cannot trust.
                HStack(spacing: 5) {
                    Image(systemName: context.appIcon)
                        .font(.system(size: 10, weight: .medium))
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

    /// Reply tapped with no live session. Explain the constraint plainly instead
    /// of showing a dead button.
    private var screenContextPrompt: some View {
        VStack(spacing: Theme.Space.sm) {
            VStack(spacing: 4) {
                Text("Screen context is off")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Keys.label)

                Text("Reply needs to read the message on screen. iOS asks you to start that yourself, and it lasts until you stop it.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Keys.secondaryLabel)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Theme.Space.md)

            primaryButton("Start screen context") {
                controller.requestScreenContext()
            }
            .padding(.horizontal, Theme.Space.sm)

            Spacer(minLength: 0)
        }
        .padding(.top, Theme.Space.xs)
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
