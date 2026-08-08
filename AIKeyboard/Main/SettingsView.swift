import SwiftUI
import AIKeyboardCore

struct SettingsView: View {
    @EnvironmentObject private var store: SharedStore
    @StateObject private var session = ScreenContextSession.shared

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Surface.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.lg) {
                        typingSection
                        aiSection
                        feedbackSection
                        moreSection
                        footer
                    }
                    .padding(.horizontal, Theme.Space.md)
                    .padding(.bottom, Theme.Space.xl)
                }
            }
            .navigationTitle("Settings")
        }
    }

    // MARK: Typing

    private var typingSection: some View {
        section("Typing") {
            ToggleRow(
                title: "Autocorrect",
                subtitle: "Commits the highlighted suggestion when you press space",
                icon: "text.badge.checkmark",
                isOn: $store.autocorrect
            )
            divider
            ToggleRow(
                title: "Auto-capitalise",
                icon: "textformat",
                isOn: $store.autocapitalise
            )
            divider
            ToggleRow(
                title: "Predictions",
                subtitle: "Show the suggestion bar above the keys",
                icon: "lightbulb",
                isOn: $store.predictions
            )
        }
    }

    // MARK: AI

    private var aiSection: some View {
        section("AI") {
            ToggleRow(
                title: "Prefer on-device",
                subtitle: "Uses Apple's local model when it can, and only falls back to the cloud when it cannot",
                icon: "cpu",
                isOn: $store.preferOnDeviceAI
            )
            divider
            HStack(spacing: Theme.Space.sm) {
                IconBadge(systemName: "slider.horizontal.3")
                Text("Default tone")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.Text.primary)
                Spacer()
                Picker("Default tone", selection: $store.defaultTone) {
                    ForEach(ToneStyle.allCases) { tone in
                        Text(tone.title).tag(tone)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
        }
    }

    // MARK: Feedback

    private var feedbackSection: some View {
        section("Feel") {
            ToggleRow(title: "Haptics", icon: "hand.tap", isOn: $store.haptics)
            divider
            ToggleRow(
                title: "Key sounds",
                subtitle: "Needs Full Access",
                icon: "speaker.wave.2",
                isOn: $store.keySounds
            )
        }
    }

    // MARK: More

    /// Reports the session rather than the stored opt-in. The setting only means
    /// the user has seen the sample; whether Reply can read anything depends on a
    /// broadcast that iOS starts and ends.
    private var screenContextSubtitle: String {
        switch session.source {
        case .capture: return session.isLive ? "Watching your screen" : "Stopped"
        case .scripted: return "Playing a sample"
        case .none: return "Off"
        }
    }

    private var moreSection: some View {
        section("More") {
            NavigationRow(
                title: "Screen context",
                subtitle: screenContextSubtitle,
                icon: "eye"
            ) {
                ScreenContextView()
            }
            divider
            NavigationRow(
                title: "Personal dictionary",
                subtitle: "Names and words we should never correct",
                icon: "character.book.closed",
                badge: "\(store.personalDictionary.count)"
            ) {
                DictionaryView()
            }
            divider
            NavigationRow(
                title: store.isSubscribed ? "Subscription" : "Upgrade to Pro",
                subtitle: store.isSubscribed ? "Active" : "Unlimited rewrites and cloud dictation",
                icon: "sparkles"
            ) {
                SubscriptionView()
            }
            divider
            Button {
                store.hasCompletedOnboarding = false
            } label: {
                HStack(spacing: Theme.Space.sm) {
                    IconBadge(systemName: "arrow.counterclockwise", tint: Theme.Text.secondary)
                    Text("Replay onboarding")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.Text.primary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Text("AI Keyboard 0.1")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.Text.secondary)
            Text("Mock build · no network, no model, no microphone")
                .font(.system(size: 12))
                .foregroundStyle(Theme.Text.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Space.xs)
    }

    // MARK: Scaffolding

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionHeader(title: title)
            Card {
                VStack(spacing: Theme.Space.sm) {
                    content()
                }
            }
        }
    }

    private var divider: some View {
        Divider().overlay(Theme.Surface.separator)
    }
}

// MARK: - Personal dictionary

struct DictionaryView: View {
    @EnvironmentObject private var store: SharedStore
    @State private var newWord = ""
    @FocusState private var isAdding: Bool

    var body: some View {
        ZStack {
            Theme.Surface.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    addField

                    if store.personalDictionary.isEmpty {
                        emptyState
                    } else {
                        wordList
                    }
                }
                .padding(.horizontal, Theme.Space.md)
                .padding(.bottom, Theme.Space.xl)
            }
        }
        .navigationTitle("Personal dictionary")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var addField: some View {
        HStack(spacing: Theme.Space.xs) {
            TextField("Add a word or name", text: $newWord)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($isAdding)
                .onSubmit(add)
                .padding(.horizontal, Theme.Space.sm)
                .frame(height: 46)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Theme.Surface.raised)
                )

            Button(action: add) {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.Text.onBrand)
                    .frame(width: 46, height: 46)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Theme.Brand.gradient)
                    )
            }
            .pressable()
            .disabled(trimmedWord.isEmpty)
            .opacity(trimmedWord.isEmpty ? 0.45 : 1)
            .accessibilityLabel("Add word")
        }
    }

    private var wordList: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionHeader(title: "\(store.personalDictionary.count) words")

            Card(padding: Theme.Space.xs) {
                VStack(spacing: 0) {
                    ForEach(Array(store.personalDictionary.enumerated()), id: \.offset) { index, word in
                        if index > 0 {
                            Divider().overlay(Theme.Surface.separator).padding(.leading, Theme.Space.xs)
                        }
                        HStack {
                            Text(word)
                                .font(.system(size: 16))
                                .foregroundStyle(Theme.Text.primary)
                            Spacer()
                            Button {
                                remove(at: index)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 17))
                                    .foregroundStyle(Theme.Text.tertiary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(word)")
                        }
                        .padding(.vertical, Theme.Space.sm)
                        .padding(.horizontal, Theme.Space.xs)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Space.xs) {
            Image(systemName: "character.book.closed")
                .font(.system(size: 34))
                .foregroundStyle(Theme.Text.tertiary)
            Text("Nothing here yet")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.Text.primary)
            Text("Add names, companies and terms autocorrect keeps getting wrong.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.Text.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.xxl)
    }

    private var trimmedWord: String {
        newWord.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func add() {
        let word = trimmedWord
        guard !word.isEmpty, !store.personalDictionary.contains(word) else { return }
        Feedback.success()
        withAnimation(Theme.Motion.quick) {
            store.personalDictionary.insert(word, at: 0)
        }
        newWord = ""
    }

    private func remove(at index: Int) {
        Feedback.modifierPress()
        withAnimation(Theme.Motion.quick) {
            _ = store.personalDictionary.remove(at: index)
        }
    }
}
