import SwiftUI

extension ActionBanner {

    // MARK: The tag on the left

    @ViewBuilder
    var leading: some View {
        switch state {
        case .hint:
            EmptyView()
        case .context:
            tag(AIAction.reply.icon, "On screen", tint: Theme.Keys.secondaryLabel)
        case .working(let action), .options(let action, _, _):
            tag(action.icon, action.title, tint: Theme.Brand.solid)
        case .failed(let action, _, _):
            tag("exclamationmark.triangle", action.title, tint: Theme.Semantic.warning)
        case .blocked(let block):
            tag(
                "exclamationmark.triangle",
                block.action?.title ?? "Dictation",
                tint: Theme.Semantic.warning)
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
    func tag(_ icon: String, _ title: String, tint: Color) -> some View {
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
    var content: some View {
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

        case .blocked(let block):
            // The same two-line shape `.failed` and `.dictationFailed` already use.
            // A refusal is the same kind of thing they are — a sentence about
            // something that did not happen — so it earns no new vocabulary.
            VStack(alignment: .leading, spacing: 0) {
                Text(block.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.Keys.label)
                    .lineLimit(1)
                caption(block.detail)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(block.title). \(block.detail)")
            .accessibilityIdentifier("banner-blocked")

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

    func caption(_ text: String) -> some View {
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
    func answer(_ text: String, language: KeyboardLanguage, size: CGFloat) -> some View {
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
}
