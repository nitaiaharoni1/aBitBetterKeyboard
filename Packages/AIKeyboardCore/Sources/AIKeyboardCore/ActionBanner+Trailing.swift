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
            switch block.remedy {
            case .none:
                dismissButton(identifier: "banner-blocked-dismiss") {
                    controller.clearBanner()
                }
            case .broadcastPicker:
                pickerChip(block)
            case .openApp(let url):
                // Compact HStack: the X lets the user decline the handoff;
                // the chip opens the app with a fresh timestamp on tap.
                HStack(spacing: Theme.Space.xxs) {
                    dismissButton(identifier: "banner-blocked-dismiss") {
                        controller.clearBanner()
                    }
                    openAppChip(url)
                }
            }

        case .dictationFailed:
            // `stopDictation(insert: false)` rather than `clearBanner`: the reason
            // lives on the session, not on the banner, so clearing this side of it
            // would leave the sentence to reappear on the next tick.
            dismissButton(identifier: "banner-dictation-dismiss") {
                controller.stopDictation(insert: false)
            }
        }
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

    /// Apple's own broadcast picker, sized to the strip.
    ///
    /// **The tap target is 10pt smaller than this in each dimension**, because
    /// `-[RPSystemBroadcastPickerView addBroadcastPickerButton]` insets its real
    /// `UIButton` by 5 on every edge. So 42 here is a 32pt target, against the 42 the
    /// deleted setup panel could afford at 52 — and the strip cannot grow to buy it
    /// back, because `Theme.Metrics.bannerHeight` is capped by the frame fingerprint
    /// rather than by taste. See `.claude/rules/screen-context.md`.
    ///
    /// The white-then-brand circle behind it belongs to `BroadcastPickerButton`
    /// itself and is deliberately not repeated here: the system assigns the glyph's
    /// colour from `UIScreen.main.isCaptured` and never inherits one, so that
    /// underlay is a correctness requirement rather than styling, and it lives with
    /// the view that knows it.
    func pickerChip(_ block: BannerState.Block) -> some View {
        BroadcastPickerButton(size: 42)
            .accessibilityLabel("Start screen context")
            .accessibilityHint("Opens the iOS screen broadcast picker. \(block.detail)")
            .accessibilityIdentifier("banner-start-broadcast")
    }

    /// A tappable chip that opens the containing app via a SwiftUI `Link`.
    ///
    /// This is the secondary, user-tapped path: the primary open was already
    /// attempted automatically when the dictation key was tapped. The
    /// `simultaneousGesture` refreshes the handoff timestamp before the URL
    /// opens, so a user who waited more than 30 seconds since the initial tap
    /// still lands a fresh request for the app to consume on cold launch.
    func openAppChip(_ url: URL) -> some View {
        Link(destination: url) {
            Text("Open AI Keyboard")
                .font(.system(size: 13, weight: .medium))
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
            TapGesture().onEnded { controller.recordDictationHandoff() }
        )
        .accessibilityIdentifier("banner-open-app")
        .accessibilityHint("Opens AI Keyboard. After it starts, swipe back to continue.")
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
