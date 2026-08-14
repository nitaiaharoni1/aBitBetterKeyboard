import AIKeyboardCore
import SwiftUI

/// The "AI" settings card: default tone picker and optional custom tone field.
struct SettingsAISection: View {
    @EnvironmentObject private var store: SharedStore

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionHeader(title: "AI")
            Card {
                VStack(spacing: Theme.Space.sm) {
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
                    .searchTarget(.defaultTone)

                    if store.prefersCustomTone {
                        customToneField
                    }

                    tonePreview

                    settingsNoteText

                    Divider.themed
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Where text goes")
                            .font(Theme.Fonts.body)
                            .foregroundStyle(Theme.Text.primary)
                        LearnMoreDisclosure(detail: Self.cloudRewriteDetail)
                    }
                }
            }
        }
    }

    /// Names what actually leaves the device, matching `RoutedIntelligence` and
    /// `CloudScreenReader` rather than a privacy-policy claim.
    private static let cloudRewriteDetail =
        "Fix, Rewrite, Tone and Reply send the current text to a server when Apple's on-device model cannot run them. That includes Hebrew. Languages Apple lists can stay on the device. Screen context sends one screenshot per Reply tap and gets back the sender, the message and its language. The picture is not saved."

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

    private var settingsNoteText: some View {
        Text(store.toneSetting.settingsNote)
            .font(Theme.Fonts.caption)
            .foregroundStyle(Theme.Text.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var tonePreview: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            if !previewCaption.isEmpty {
                Text(previewCaption)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Text.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                previewBubble
                Spacer(minLength: 0)
            }
        }
    }

    private var previewCaption: String {
        if store.prefersCustomTone {
            return customLine.isEmpty ? "" : "Rewrites in the line you wrote."
        }
        return store.defaultTone.previewCaption
    }

    private var customLine: String {
        store.customTone.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var previewBubble: some View {
        let quotesCustom = store.prefersCustomTone && !customLine.isEmpty
        return Group {
            if quotesCustom {
                bubbleLine(customLine)
            } else {
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    bubbleLine(store.defaultTone.previewEnglish)
                    bubbleLine(store.defaultTone.previewHebrew)
                }
            }
        }
        .padding(.horizontal, Theme.Space.sm)
        .padding(.vertical, Theme.Space.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            quotesCustom ? "Your tone" : "Sample rewrite in \(store.defaultTone.title)")
    }

    private func bubbleLine(_ text: String) -> some View {
        Text(text)
            .font(Theme.Fonts.body)
            .foregroundStyle(Theme.Text.onBrand)
            .fixedSize(horizontal: false, vertical: true)
    }
}
