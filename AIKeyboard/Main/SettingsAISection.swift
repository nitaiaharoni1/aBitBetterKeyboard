import AIKeyboardCore
import SwiftUI

/// The "AI" settings card: default tone picker and optional custom tone field.
///
/// **Both controls are affected by Full Access.** `SharedStore.toneSetting`
/// reads `defaultTone`, `prefersCustomTone` and `customTone` across the App
/// Group — `ToneSetting.swift`'s `storedDefaultTone` and this section's own
/// two accessors — so a tone picked here is inert in the keyboard until Full
/// Access is confirmed. See `FullAccessNeededBanner`.
struct SettingsAISection: View {
    @EnvironmentObject private var store: SharedStore
    let setup: SetupState

    /// Mirrors `LayoutView.fullAccessMessage`'s hedge: `setup.fullAccess` can
    /// only ever *confirm* a yes, so this says "once Full Access is on"
    /// rather than asserting it is off right now.
    private static let fullAccessMessage =
        "The keyboard can only read your tone once Full Access is on. Until then the one-tap "
        + "rewrite button uses Normal, whatever is chosen here."

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            if setup.fullAccess != .confirmed {
                FullAccessNeededBanner(message: Self.fullAccessMessage, context: "ai")
            }
            SectionHeader(title: "AI")
            Card {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    ZStack {
                        HStack(spacing: Theme.Space.xs) {
                            IconBadge(systemName: "slider.horizontal.3")
                            Text("Default tone")
                                .font(Theme.Fonts.body)
                                .foregroundStyle(Theme.Text.primary)
                            Spacer(minLength: Theme.Space.xs)
                            selectionChip
                        }
                        .accessibilityHidden(true)

                        Menu {
                            Picker("Default tone", selection: toneChoice) {
                                ForEach(ToneStyle.allCases) { tone in
                                    Label(tone.title, systemImage: tone.icon)
                                        .tag(Optional(tone))
                                }
                                Label(
                                    ToneSetting.customTitle,
                                    systemImage: ToneSetting.customIcon
                                )
                                .tag(ToneStyle?.none)
                            }
                        } label: {
                            Color.clear
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .contentShape(Rectangle())
                        }
                        .menuIndicator(.hidden)
                        .buttonStyle(.plain)
                        .accessibilityLabel("Default tone, \(selectedToneTitle)")
                    }
                    .frame(minHeight: 44)
                    .searchTarget(.defaultTone)

                    if store.prefersCustomTone {
                        customToneField
                    }

                    Text(toneSentence)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Text.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Drawn in the row, not as `Menu`'s label. The menu host is a clear
    /// overlay so its UIKit chrome cannot drift off the card while scrolling.
    private var selectionChip: some View {
        HStack(spacing: 4) {
            Image(systemName: selectedToneIcon)
                .font(.system(size: 13, weight: .medium))
            Text(selectedToneTitle)
                .font(Theme.Fonts.micro)
                .lineLimit(1)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 8, weight: .semibold))
        }
        .foregroundStyle(Theme.Brand.solid)
    }

    /// `nil` is the user's own tone rather than a `ToneStyle`, because
    /// `ToneStyle`'s raw values are the persisted setting and its cases are
    /// the chips in the keyboard's tone panel — see `ToneSetting`.
    private var toneChoice: Binding<ToneStyle?> {
        Binding(
            get: { store.prefersCustomTone ? nil : store.defaultTone },
            set: { choice in
                guard let choice else {
                    store.prefersCustomTone = true
                    return
                }
                store.prefersCustomTone = false
                store.defaultTone = choice
            }
        )
    }

    /// One line, in the user's words, describing how they want to sound.
    ///
    /// Deliberately a single-line field with a hard cap: this text is handed to a
    /// model as its register, and a paragraph stops being a register.
    private var customToneField: some View {
        TextField(
            "Short and blunt, no pleasantries",
            text: Binding(get: { store.customTone }, set: { store.customTone = $0 })
        )
        .font(Theme.Fonts.body)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .padding(.horizontal, Theme.Space.sm)
        .frame(height: 44)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.Surface.background)
        )
        .accessibilityIdentifier("row-custom-tone")
        .accessibilityLabel("Your own tone")
    }

    private var selectedToneTitle: String {
        store.prefersCustomTone ? ToneSetting.customTitle : store.defaultTone.title
    }

    private var selectedToneIcon: String {
        store.prefersCustomTone ? ToneSetting.customIcon : store.defaultTone.icon
    }

    private var toneSentence: String {
        if store.prefersCustomTone {
            return "Write one line for how you want to sound."
        }
        return store.defaultTone.previewCaption
    }
}
