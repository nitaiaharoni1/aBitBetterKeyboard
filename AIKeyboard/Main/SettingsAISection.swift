import AIKeyboardCore
import SwiftUI

/// The "AI" settings card: cloud model row, default tone picker, and optional
/// custom tone field.
///
/// **The cloud row leads, because without it most of this section does
/// nothing.** Apple's on-device model has no Hebrew, so on a stock install
/// every Fix, Rewrite, Tone and Reply in the keyboard's primary language fails
/// with "no cloud model is set up" — and this screen used to answer that with a
/// tone picker and a "Prefer on-device" switch nothing read. See `CloudModelView`
/// for why the setting lives here rather than on Screen Context.
struct SettingsAISection: View {
    @EnvironmentObject private var store: SharedStore

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionHeader(title: "AI")
            Card {
                VStack(spacing: Theme.Space.sm) {
                    CloudModelRow()
                    Divider.themed
                    HStack(spacing: Theme.Space.sm) {
                        IconBadge(systemName: "slider.horizontal.3")
                        Text("Default tone")
                            .font(Theme.Fonts.body)
                            .foregroundStyle(Theme.Text.primary)
                        Spacer()
                        Picker("Default tone", selection: toneChoice) {
                            ForEach(ToneStyle.allCases) { tone in
                                Text(tone.title).tag(Optional(tone))
                            }
                            Text(ToneSetting.customTitle).tag(ToneStyle?.none)
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }

                    if store.prefersCustomTone {
                        customToneField
                    }
                }
            }
        }
    }

    /// The picker's seventh option. `nil` is the user's own tone rather than a
    /// seventh `ToneStyle`, because `ToneStyle`'s raw values are the persisted
    /// setting and its cases are the chips in the keyboard's tone panel — see
    /// `ToneSetting`.
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
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
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

            // The sentence lives on `ToneSetting`, not here: it names a control,
            // it named the wrong one (a ✦ button nothing draws), and the app
            // target has no test host to catch that. See `ToneSetting.settingsNote`.
            Text(store.toneSetting.settingsNote)
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Text.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
