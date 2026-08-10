import AIKeyboardCore
import SwiftUI

/// The "Typing" settings card: autocorrect, auto-capitalise, predictions,
/// number row, and keyboard layout.
struct SettingsTypingSection: View {
    @EnvironmentObject private var store: SharedStore

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionHeader(title: "Typing")
            Card {
                VStack(spacing: Theme.Space.sm) {
                    ToggleRow(
                        title: "Autocorrect",
                        subtitle: "Commits the highlighted suggestion when you press space",
                        icon: "text.badge.checkmark",
                        isOn: $store.autocorrect
                    )
                    Divider.themed
                    ToggleRow(
                        title: "Auto-capitalise",
                        icon: "textformat",
                        isOn: $store.autocapitalise
                    )
                    Divider.themed
                    ToggleRow(
                        title: "Predictions",
                        subtitle: "Show the suggestion bar above the keys",
                        icon: "lightbulb",
                        isOn: $store.predictions
                    )
                    Divider.themed
                    ToggleRow(
                        title: "Number row",
                        subtitle: "Digits above the letters. Makes the keyboard taller.",
                        icon: "textformat.123",
                        isOn: numberRowBinding
                    )
                    Divider.themed
                    NavigationRow(
                        title: "Keyboard layout",
                        subtitle: "Presets, key size, and what each key does",
                        icon: "square.grid.3x2",
                        badge: layoutSummary
                    ) {
                        // Deliberately parameterless. Passing `store.keyboardLayout` here
                        // makes the pushed editor a function of the store, so tapping its
                        // Done button rebuilds it while it dismisses itself. See
                        // `LayoutView.init`.
                        LayoutView()
                    }
                }
            }
        }
    }

    /// Writes `showsNumberRow` and, if that moves the layout away from its
    /// preset, clears the preset too — the same thing `LayoutEditorModel.draft`'s
    /// `didSet` does for every edit made inside the layout editor itself.
    private var numberRowBinding: Binding<Bool> {
        Binding(
            get: { store.keyboardLayout.showsNumberRow },
            set: { newValue in
                store.keyboardLayout.showsNumberRow = newValue
                if let preset = store.keyboardLayout.preset,
                    LayoutPreset.named(preset)?.customization != store.keyboardLayout
                {
                    store.keyboardLayout.preset = nil
                }
            }
        )
    }

    /// The preset's name, or that it has been edited away from one.
    private var layoutSummary: String {
        guard let id = store.keyboardLayout.preset, let preset = LayoutPreset.named(id) else {
            return "Custom"
        }
        return preset.name
    }
}
