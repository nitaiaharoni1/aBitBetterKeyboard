import SwiftUI
import AIKeyboardCore

/// The real keyboard, typing into an in-memory document. Used in onboarding and
/// in the playground so the product can be felt before it is installed.
struct KeyboardPreview: View {
    @StateObject private var target = MockTextTarget()
    @StateObject private var controller: KeyboardController

    private let showsDocument: Bool
    private let placeholder: String
    private let seedText: String
    private let hint: String?

    init(
        seedText: String = "",
        language: KeyboardLanguage = .english,
        showsDocument: Bool = true,
        placeholder: String = "Type something…",
        hint: String? = nil
    ) {
        let document = MockTextTarget(text: seedText)
        _target = StateObject(wrappedValue: document)
        _controller = StateObject(
            wrappedValue: KeyboardController(target: document, language: language)
        )
        self.showsDocument = showsDocument
        self.placeholder = placeholder
        self.seedText = seedText
        self.hint = hint
    }

    var body: some View {
        VStack(spacing: 0) {
            if let hint, showsHint {
                hintLine(hint)
            }
            if showsDocument {
                document
            }
            KeyboardView(controller: controller)
        }
        // On the container, not on the hint: the hint is removed from the tree
        // when it stops applying, so a modifier attached to it is gone before it
        // could animate anything.
        .animation(Theme.Motion.quick, value: showsHint)
        .onChange(of: target.text) { _, _ in
            controller.refreshSuggestions()
        }
    }

    /// The hint names the next useful thing to do *with the sentence that is
    /// already there*, so it has to leave the moment the user does something with
    /// it — typing, deleting, or opening the AI menu and taking a rewrite. An
    /// instruction that outlives the state it describes is how "type a sentence"
    /// ended up printed above a sentence.
    private var showsHint: Bool { !seedText.isEmpty && target.text == seedText }

    private func hintLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            SparkleMark(size: 13)
            Text(text)
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Text.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.sm)
        .padding(.top, Theme.Space.sm)
        .transition(.opacity)
        .accessibilityElement(children: .combine)
    }

    private var document: some View {
        ScrollView {
            Text(target.text.isEmpty ? placeholder : target.text)
                .font(Theme.Fonts.body)
                .foregroundStyle(target.text.isEmpty ? Theme.Text.tertiary : Theme.Text.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Space.sm)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                        .fill(Theme.Surface.raised)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                        .strokeBorder(Theme.Surface.separator, lineWidth: 1)
                )
                .padding(Theme.Space.sm)
        }
        .frame(maxHeight: .infinity)
        .scrollBounceBehavior(.basedOnSize)
    }
}
