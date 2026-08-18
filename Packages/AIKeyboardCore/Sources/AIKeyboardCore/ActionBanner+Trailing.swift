import SwiftUI

extension ActionBanner {

    // MARK: The button on the right

    @ViewBuilder
    var trailing: some View {
        switch state {
        case .hint, .context:
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
            dismissButton(identifier: "banner-dismiss") { controller.clearBanner() }

        case .blocked(let block):
            switch Self.blockedTrailing(for: block.remedy) {
            case .dismiss:
                dismissButton(identifier: "banner-blocked-dismiss") {
                    controller.clearBanner()
                }
            case .dismissAndOpenApp(let url):
                // Compact HStack: the X lets the user decline the handoff;
                // the chip opens the app. Dictation refreshes its timestamp
                // on tap; screen context does not auto-start.
                HStack(spacing: Theme.Space.xxs) {
                    dismissButton(identifier: "banner-blocked-dismiss") {
                        controller.clearBanner()
                    }
                    openAppChip(url)
                }
            case .dismissAndOpenCopyClip:
                // The same pair, one panel closer: nothing leaves the keyboard
                // here, so there is no handoff to decline and the × is only a
                // way to put the strip away.
                HStack(spacing: Theme.Space.xxs) {
                    dismissButton(identifier: "banner-blocked-dismiss") {
                        controller.clearBanner()
                    }
                    copyClipChip
                }
            }
        }
    }

    /// Opens CopyClip, where `UIPasteControl` is drawn for the generation the
    /// keyboard was not allowed to read.
    ///
    /// **Named "Paste" rather than "CopyClip", because Paste is what the user
    /// does next.** The panel this opens draws Apple's own paste button under
    /// the same word, so the label and the control it leads to say one thing.
    /// `show(.copyclip)` already calls `refreshCopyClip(.userAsked)`, which is
    /// what resolves an image-only generation without any of this being drawn a
    /// second time.
    var copyClipChip: some View {
        button("Paste", tint: Theme.Brand.gradient, filled: true) {
            controller.show(.copyclip)
        }
        .accessibilityLabel("Open CopyClip")
        .accessibilityIdentifier("banner-open-copyclip")
        .accessibilityHint("Opens CopyClip, where Paste lets the copied message in.")
    }

    /// Closes the strip. An × rather than a word, so the trailing chip stays a
    /// target and the detail beside it keeps the width it needs to finish its
    /// sentence. `label` is VoiceOver only.
    func dismissButton(
        identifier: String, label: String = "Dismiss", action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(Theme.Glyph.medium(12))
                .foregroundStyle(Theme.Keys.secondaryLabel)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                        .fill(Theme.Keys.card)
                )
                .contentShape(Rectangle())
        }
        .pressable()
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    /// Which of the answers is showing. Tappable as well as swipeable, because a
    /// swipe on a 56pt strip sitting directly above the keys competes with the
    /// scroll of whatever the host app is showing, and because a dot is the only
    /// part of this a VoiceOver user can address.
    func pager(count: Int, index: Int) -> some View {
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

    /// What the trailing slot draws for a refusal. The broadcast picker is not
    /// here: a record-dot chip was the only start control and it read as already
    /// recording. The picker lives on the sentence; this is ×, or × plus Open.
    enum BlockedTrailing: Equatable {
        case dismiss
        case dismissAndOpenApp(URL)
        case dismissAndOpenCopyClip
    }

    static func blockedTrailing(for remedy: BannerState.Block.Remedy) -> BlockedTrailing {
        switch remedy {
        case .none, .broadcastPicker:
            return .dismiss
        case .openApp(let url):
            return .dismissAndOpenApp(url)
        case .copyclip:
            return .dismissAndOpenCopyClip
        }
    }

    /// A tappable chip that opens the containing app via a SwiftUI `Link`.
    ///
    /// This is the secondary, user-tapped path: the primary open was already
    /// attempted automatically when the key was tapped. Dictation refreshes
    /// its handoff timestamp here so a wait longer than 30 seconds still
    /// auto-starts the mic. Screen context must not write that timestamp.
    /// The visible label is short on purpose: the product name ate the
    /// refusal sentence on a 320pt phone. VoiceOver still speaks the full name.
    func openAppChip(_ url: URL) -> some View {
        Link(destination: url) {
            Text("Open app")
                .font(
                    .system(
                        size: Self.sentenceFontSize(base: 13, dynamicTypeSize: dynamicTypeSize),
                        weight: .medium)
                )
                .foregroundStyle(Theme.Text.onBrand)
                .lineLimit(1)
                .padding(.horizontal, Theme.Space.sm)
                .frame(height: 32)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                        .fill(Theme.Brand.gradient)
                )
                .contentShape(Rectangle())
        }
        .pressable()
        .simultaneousGesture(
            TapGesture().onEnded { controller.recordDictationHandoffIfNeeded(for: url) }
        )
        .accessibilityLabel("Open aBitBetterKeyboard")
        .accessibilityIdentifier("banner-open-app")
        .accessibilityHint("Opens aBitBetterKeyboard. After it starts, swipe back to continue.")
    }

    /// `LinearGradient?` rather than a generic `ShapeStyle`, because the one
    /// unfilled caller passes `nil` and a generic parameter cannot be inferred
    /// from it. Every filled caller has a gradient to hand anyway: the brand one,
    /// or the flat record red spelled as a gradient of itself.
    func button(
        _ title: String, tint: LinearGradient?, filled: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(
                    .system(
                        size: Self.sentenceFontSize(base: 13, dynamicTypeSize: dynamicTypeSize),
                        weight: .medium)
                )
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
