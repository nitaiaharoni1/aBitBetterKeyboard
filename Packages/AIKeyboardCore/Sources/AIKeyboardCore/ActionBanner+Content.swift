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
        case .options(let action, _, _):
            // **Amber when the answer is a best effort**, which means the on-device
            // model answered in a language Apple does not list as supported because
            // no cloud engine was reachable. `AIResultPanel` said so in a sentence
            // and had room for one; a 48pt strip does not, so the tag carries it and
            // the accessibility label below carries the words. The result is still
            // worth offering — the user can see their own sentence in the field
            // underneath — but it must not be presented with the same confidence.
            let bestEffort = controller.aiProvenance?.isBestEffort == true
            tag(
                bestEffort ? "info.circle" : action.icon,
                action.title,
                tint: bestEffort ? Theme.Semantic.warning : Theme.Brand.solid)
        case .failed(let action, _, _):
            tag("exclamationmark.triangle", action.title, tint: Theme.Semantic.warning)
        case .blocked(let block):
            tag(
                "exclamationmark.triangle",
                block.action?.title ?? "Dictation",
                tint: Theme.Semantic.warning)
        }
    }

    /// The action's name, always in words beside its glyph.
    ///
    /// A glyph alone would repeat the mistake the one-tap rewrite button already
    /// made twice: `sparkle` and `sparkles` are one drawing at two counts, and
    /// `figure.wave` in a keyboard reads as a contacts button. Whatever the banner
    /// is doing, it says so.
    /// **The countdown replaces the word, and only in the last minute.**
    ///
    /// A session closes itself, and `DictationPanel` used to print the remaining
    /// seconds in its header. The panel is deleted and the strip has one line, so
    /// this is the one thing that header said which was worth the room: a clock
    /// running for the whole session is one the user is invited to watch, and a
    /// clock that appears is news.
    ///
    /// What did not survive is the `עב ⟷ EN` badge naming the languages heard. The
    /// transcript beside it is already written in its own script, so the badge was
    /// the cheaper of the two to lose.
    func tag(_ icon: String, _ title: String, tint: Color) -> some View {
        VStack(spacing: 1) {
            Image(systemName: icon)
                .font(Theme.Glyph.medium(13))
            Text(title.uppercased())
                .font(
                    .system(
                        size: Self.badgeFontSize(base: 8, dynamicTypeSize: dynamicTypeSize),
                        weight: .semibold)
                )
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
                    .font(
                        .system(
                            size: Self.badgeFontSize(base: 10, dynamicTypeSize: dynamicTypeSize),
                            weight: .semibold)
                    )
                    .foregroundStyle(Theme.Keys.secondaryLabel)
                answer(message, language: language, size: 13)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("From \(sender): \(message)")

        case .options(_, let options, let index):
            let option = options[index]
            VStack(alignment: .leading, spacing: 1) {
                if !option.label.isEmpty {
                    Text(option.label.uppercased())
                        .font(
                            .system(
                                size: Self.badgeFontSize(base: 8, dynamicTypeSize: dynamicTypeSize),
                                weight: .semibold)
                        )
                        .tracking(0.4)
                        .foregroundStyle(Theme.Brand.solid)
                        .lineLimit(1)
                }
                answer(option.text, language: option.language, size: 14)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                (options.count > 1
                    ? "\(option.label). \(option.text). Option \(index + 1) of \(options.count)"
                    : "\(option.label). \(option.text)")
                    // The sentence the deleted panel printed under the answer. It has
                    // no line of its own on a one-line strip, and the amber tag alone
                    // says nothing to somebody who cannot see it.
                    + (controller.aiProvenance?.isBestEffort == true
                        ? ". Best effort, this language isn't fully supported on device"
                        : ""))

        case .failed(_, let title, let detail):
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(
                        .system(
                            size: Self.sentenceFontSize(base: 13, dynamicTypeSize: dynamicTypeSize),
                            weight: .medium)
                    )
                    .foregroundStyle(Theme.Keys.label)
                    .lineLimit(1)
                caption(detail)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title). \(detail)")

        case .blocked(let block):
            // The same multi-line shape `.failed` already uses. A refusal is the
            // same kind of thing it is — a sentence about something that did not
            // happen — so it earns no new vocabulary.
            VStack(alignment: .leading, spacing: 2) {
                Text(block.title)
                    .font(
                        .system(
                            size: Self.sentenceFontSize(base: 13, dynamicTypeSize: dynamicTypeSize),
                            weight: .medium)
                    )
                    .foregroundStyle(Theme.Keys.label)
                    .lineLimit(1)
                caption(block.detail)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(block.title). \(block.detail)")
            .accessibilityHidden(block.startsBroadcastFromMessage)
            .overlay {
                // A SwiftUI tap cannot start a broadcast. The overlay *is*
                // ReplayKit's button, stretched over the sentence; trailing is ×.
                if block.startsBroadcastFromMessage {
                    BroadcastPickerButton.overlay(
                        label: "\(block.title). \(block.detail)",
                        hint: "Opens the iOS screen broadcast picker.",
                        identifier: "banner-start-broadcast")
                }
            }
            .accessibilityIdentifier("banner-blocked")
        }
    }

    func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: Self.sentenceFontSize(base: 11, dynamicTypeSize: dynamicTypeSize)))
            .foregroundStyle(Theme.Keys.secondaryLabel)
            // **Two lines, and `Theme.Metrics.bannerHeight` is why they fit.** The
            // strip paid 11pt to grow the letter keys (69 → 58). Three 11pt lines
            // plus the title overflow that frame and paint the suggestion bar.
            // Scale a hair before truncating; past two lines the honest mitigation
            // is still the accessibility label. `sentenceFontSize` caps Dynamic
            // Type's own growth at 3pt over that 11 for the same reason: three
            // lines is already the ceiling this frame allows.
            .lineLimit(2)
            .minimumScaleFactor(0.85)
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
            .font(.system(size: Self.sentenceFontSize(base: size, dynamicTypeSize: dynamicTypeSize)))
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
