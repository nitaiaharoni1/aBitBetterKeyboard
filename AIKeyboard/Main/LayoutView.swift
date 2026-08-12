import SwiftUI
import AIKeyboardCore

/// The layout editor: the real keyboard above, the controls below.
///
/// **The canvas is the real `KeyboardView`.** Nothing here redraws the keyboard
/// for editing, so what the user arranges is literally what they get — which is
/// the whole reason the keyboard UI lives in the package rather than in the
/// extension. Taps and drags land on a transparent layer over it, because
/// `KeyView`'s own gesture types and this one has to select.
///
/// **Every edit has a non-drag route, and that is not a fallback.** Drag and
/// drop is unusable under VoiceOver, so the row list below the canvas carries
/// Move left, Move right, a width slider and an action picker for every key. It
/// is also the half that shipped first, because it is the half that works for
/// everybody.
struct LayoutView: View {

    @EnvironmentObject private var store: SharedStore
    @Environment(\.dismiss) private var dismiss

    /// **Both of these are default-initialised and filled in `.task`, and that is
    /// not a style choice.**
    ///
    /// `@StateObject(wrappedValue:)` takes an autoclosure, so a property
    /// initialiser is deferred until the view is first rendered — but assigning
    /// `_model`/`_canvas` inside `init` is not: it runs whenever the initialiser
    /// runs. This view is a `NavigationRow` destination inside a `ScrollView`
    /// rather than a `List`, so SwiftUI builds every destination eagerly on every
    /// `SettingsView` body evaluation. Constructing a `KeyboardController` there
    /// meant a fresh Combine subscription to `ScreenContextSession.shared` and a
    /// full `UITextChecker` pass through `refreshSuggestions()` on every render of
    /// the Settings screen — and tapping Done writes to the store, which
    /// re-renders Settings, which builds another one. The app hung hard enough
    /// that four UI tests timed out without leaving a crash report.
    @StateObject private var model = LayoutEditorModel(layout: .default)
    @StateObject private var canvas = KeyboardController(
        target: MockTextTarget(), language: .english)

    @State private var hasLoaded = false

    /// Where each editable key ended up on the canvas, in the overlay's own
    /// coordinate space. Filled by a preference the keyboard publishes.
    @State private var keyFrames: [UUID: CGRect] = [:]
    @State private var dragging: SlotSpec?
    @State private var dragLocation: CGPoint = .zero

    /// **Takes nothing, and that is the fix for a hang.**
    ///
    /// It used to be `LayoutView(layout: store.keyboardLayout)`. A
    /// `NavigationLink` destination inside a `ScrollView` is rebuilt on every
    /// `SettingsView` body evaluation, and reading the store there made the
    /// *pushed* view a function of the store — so tapping Done, which writes the
    /// store, rebuilt the screen the user was standing on while it was dismissing
    /// itself. The app wedged at 100% CPU with an empty accessibility tree, which
    /// reads as a crash and leaves no crash report. The editor reads its starting
    /// point from the store itself, once, in `.task`.
    init() {}

    var body: some View {
        ZStack {
            Theme.Surface.background.ignoresSafeArea()

            VStack(spacing: 0) {
                canvasSection
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.lg) {
                        LayoutPresetSection(model: model)
                        if let selection = model.selection,
                            model.rowKind(of: selection) != nil
                        {
                            LayoutKeyInspectorSection(model: model, slot: selection)
                        } else {
                            LayoutGeometrySection(model: model)
                        }
                        LayoutRowsSection(model: model)
                        LayoutAddKeySection(model: model)
                        LayoutProblemsSection(model: model)
                    }
                    .padding(.horizontal, Theme.Space.md)
                    .padding(.vertical, Theme.Space.md)
                }
            }
        }
        .navigationTitle("Keyboard layout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    model.undo()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .disabled(!model.canUndo)
                .accessibilityIdentifier("layout-undo")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    store.keyboardLayout = model.draft
                    dismiss()
                }
                .fontWeight(.semibold)
                .disabled(!model.isUsable)
                .accessibilityIdentifier("layout-done")
            }
        }
        // The canvas is a second controller with its own copy of the layout, so it
        // has to be told. One direction only: the model is the truth and the
        // canvas draws it.
        .onChange(of: model.draft) { _, layout in canvas.apply(layout) }
        .task {
            // Once. `.task` runs again if the view identity changes, and re-seeding
            // would throw away edits in progress.
            guard !hasLoaded else { return }
            hasLoaded = true
            // Read once, from the store, at the moment the editor opens. Not a
            // parameter: see `init`.
            let initialLayout = store.storedKeyboardLayout
            // **`true`, even though there is no keyboard to switch to inside the
            // app.** The globe requirement belongs to the device, and the phone
            // this editor is running on is the phone the keyboard will run on, so
            // the editor must refuse to remove the key exactly as the keyboard
            // would.
            canvas.showsGlobeKey = true
            // Assigned rather than edited: this is the starting point, not a
            // change, so it must not land on the undo stack.
            model.draft = initialLayout
            canvas.apply(initialLayout)
        }
    }

    // MARK: Canvas

    private var canvasSection: some View {
        VStack(spacing: 0) {
            KeyboardView(controller: canvas)
                .allowsHitTesting(false)
                .onPreferenceChange(KeyFramesKey.self) { frames in
                    keyFrames = Self.mapFrames(frames, to: editableSlots)
                }
                .overlay { selectionOverlay }
            Text("Tap a key to edit it. Hold and drag to move it.")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Text.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Space.xs)
            Divider().overlay(Theme.Surface.separator)
        }
        .background(Theme.Keys.background)
    }

    /// The keys the canvas lets you touch. The letter rows are deliberately not
    /// among them: they are extracted from Apple's own layout data for 64
    /// languages and are not a thing anybody gets to rearrange.
    private var editableSlots: [SlotSpec] {
        model.draft.bottomRow + model.draft.cursorRow
    }

    /// Matches the keyboard's compiled key ids back to the model's slots.
    ///
    /// A compiled key is `char-,#a1b2c3d4`: the suffix is the first eight
    /// characters of the slot's `UUID`, which is what makes two commas on one row
    /// two identities. Static so `LayoutFrameMappingTests` can drive it.
    static func mapFrames(_ frames: [String: CGRect], to slots: [SlotSpec]) -> [UUID: CGRect] {
        var mapped: [UUID: CGRect] = [:]
        for slot in slots {
            let suffix = "#\(slot.id.uuidString.prefix(8))"
            if let match = frames.first(where: { $0.key.hasSuffix(suffix) }) {
                mapped[slot.id] = match.value
            }
        }
        return mapped
    }

    private var selectionOverlay: some View {
        ZStack(alignment: .topLeading) {
            ForEach(editableSlots) { slot in
                if let frame = keyFrames[slot.id] {
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: frame.width, height: frame.height)
                        .overlay {
                            if model.selection?.id == slot.id {
                                RoundedRectangle(
                                    cornerRadius: Theme.Radius.key, style: .continuous
                                )
                                .strokeBorder(Theme.Brand.solid, lineWidth: 2)
                            }
                        }
                        .opacity(dragging?.id == slot.id ? 0.3 : 1)
                        .position(x: frame.midX, y: frame.midY)
                        .onTapGesture { model.selection = slot }
                        .gesture(dragGesture(slot))
                        // The overlay is what receives touches, so it carries the
                        // key's whole accessible identity. The keyboard beneath has
                        // hit testing off and is hidden from the reader.
                        .accessibilityElement()
                        .accessibilityLabel(accessibilityLabel(for: slot))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityIdentifier("canvas-\(slot.action.title)")
                }
            }

            if let dragging, let frame = keyFrames[dragging.id] {
                RoundedRectangle(cornerRadius: Theme.Radius.key, style: .continuous)
                    .fill(Theme.Brand.solid.opacity(0.3))
                    .frame(width: frame.width, height: frame.height)
                    .position(dragLocation)
                    .allowsHitTesting(false)
            }
        }
        // The whole canvas is a picture of the keyboard; the reader gets the keys,
        // not the rows around them.
        .accessibilityElement(children: .contain)
    }

    private func accessibilityLabel(for slot: SlotSpec) -> String {
        guard let kind = model.rowKind(of: slot) else { return slot.action.title }
        let keys = model.row(kind)
        let position = (keys.firstIndex(of: slot) ?? 0) + 1
        return "\(slot.action.title), key \(position) of \(keys.count), \(kind.title)"
    }

    private func dragGesture(_ slot: SlotSpec) -> some Gesture {
        LongPressGesture(minimumDuration: 0.25)
            .onEnded { _ in
                dragging = slot
                model.selection = slot
                Feedback.modifierPress()
            }
            .sequenced(before: DragGesture(coordinateSpace: .local))
            .onChanged { value in
                guard case .second(_, let drag?) = value else { return }
                dragLocation = drag.location
            }
            .onEnded { value in
                defer { dragging = nil }
                guard case .second(_, let drag?) = value, let dragging else { return }
                // Over the letters, or off the canvas: put it back. A drop that
                // lands nowhere must not silently move the key to row zero.
                guard let kind = rowKind(atY: drag.location.y) else { return }
                let frames = model.row(kind)
                    .filter { $0.id != dragging.id }
                    .compactMap { keyFrames[$0.id] }
                let index = LayoutEditorModel.insertionIndex(at: drag.location.x, in: frames)
                model.move(dragging, to: kind, at: index)
                Feedback.success()
            }
    }

    /// Which editable row a y coordinate is over. Nil over the letters, which is
    /// what makes them refuse the drop.
    private func rowKind(atY y: CGFloat) -> LayoutEditorModel.RowKind? {
        for kind in [LayoutEditorModel.RowKind.bottom, .cursor] {
            let frames = model.row(kind).compactMap { keyFrames[$0.id] }
            guard let first = frames.first else { continue }
            if y >= first.minY - 6, y <= first.maxY + 6 { return kind }
        }
        return nil
    }
}

// MARK: - Previews

#if DEBUG

/// Wrapped in a `NavigationStack` because the editor's Done button lives in a
/// toolbar, and inside one it is reached the same way `SettingsView` reaches
/// it — pushed, owning its own state, reading the store once in `.task`.
#Preview {
    NavigationStack {
        LayoutView()
    }
    .environmentObject(SharedStore.shared)
}

#endif
