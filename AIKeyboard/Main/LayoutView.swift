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
    @StateObject private var model = LayoutEditorModel(layout: .default, showsGlobe: true)
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
                        presetStrip
                        if let selection = model.selection,
                            model.rowKind(of: selection) != nil
                        {
                            keyInspector(selection)
                        } else {
                            geometrySection
                        }
                        rowLists
                        addDrawer
                        problems
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
                                .strokeBorder(Theme.Brand.gradient, lineWidth: 2)
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

    // MARK: Presets

    private var presetStrip: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionHeader(title: "Presets")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Space.sm) {
                    ForEach(LayoutPreset.all) { preset in
                        presetCard(preset)
                    }
                }
                .padding(2)
            }
            if model.draft.preset == nil, let base = LayoutPreset.named(model.draft.basedOn) {
                HStack {
                    Text("Custom, from \(base.name)")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Text.secondary)
                    Spacer()
                    Button("Reset") { model.reset() }
                        .font(.system(size: 13, weight: .semibold))
                        .accessibilityIdentifier("layout-reset")
                }
            }
        }
    }

    private func presetCard(_ preset: LayoutPreset) -> some View {
        let isSelected = model.draft.preset == preset.id
        return Button {
            model.apply(preset: preset)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                LayoutThumbnail(layout: preset.customization)
                    .frame(width: 96, height: 58)
                Text(preset.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Text.primary)
                Text(preset.summary)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Text.secondary)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
            }
            .frame(width: 112, alignment: .leading)
            .padding(Theme.Space.sm)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                    .fill(Theme.Surface.raised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? AnyShapeStyle(Theme.Brand.gradient) : AnyShapeStyle(Color.clear),
                        lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("preset-\(preset.id)")
        .accessibilityLabel(preset.name)
        .accessibilityValue(isSelected ? "Selected" : "")
        .accessibilityHint(preset.summary)
    }

    // MARK: Geometry

    private var geometrySection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionHeader(title: "Size and rows")
            Card {
                VStack(spacing: Theme.Space.sm) {
                    slider(
                        "Key height", value: model.draft.geometry.keyHeight,
                        range: LayoutGeometry.keyHeightRange, unit: "pt",
                        identifier: "layout-key-height"
                    ) { model.setKeyHeight($0) }
                    divider
                    slider(
                        "Row spacing", value: model.draft.geometry.rowSpacing,
                        range: LayoutGeometry.rowSpacingRange, unit: "pt",
                        identifier: "layout-row-spacing"
                    ) { model.setRowSpacing($0) }
                    divider
                    Toggle(
                        "Number row",
                        isOn: Binding(
                            get: { model.draft.showsNumberRow },
                            set: { model.setNumberRow(enabled: $0) })
                    )
                    .font(.system(size: 16))
                    .accessibilityIdentifier("layout-number-row")
                    divider
                    Toggle(
                        "Extra row",
                        isOn: Binding(
                            get: { !model.draft.cursorRow.isEmpty },
                            set: { model.setExtraRow(enabled: $0) })
                    )
                    .font(.system(size: 16))
                    .accessibilityIdentifier("layout-extra-row")
                    divider
                    VStack(alignment: .leading, spacing: 4) {
                        Text("One-handed")
                            .font(.system(size: 15))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Picker(
                            "One-handed",
                            selection: Binding(
                                get: { model.draft.geometry.reach },
                                set: { model.setReach($0) })
                        ) {
                            Text("Off").tag(Reach.full)
                            Text("Left").tag(Reach.left)
                            Text("Right").tag(Reach.right)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .accessibilityIdentifier("layout-reach")
                    }
                }
            }
        }
    }

    private func slider(
        _ title: String, value: CGFloat, range: ClosedRange<CGFloat>, unit: String,
        identifier: String, set: @escaping (CGFloat) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.system(size: 15))
                Spacer()
                Text("\(Int(value))\(unit)")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Theme.Text.secondary)
                    .monospacedDigit()
            }
            Slider(
                value: Binding(get: { Double(value) }, set: { set(CGFloat($0)) }),
                in: Double(range.lowerBound)...Double(range.upperBound), step: 1
            )
            .accessibilityIdentifier(identifier)
            .accessibilityLabel(title)
            .accessibilityValue("\(Int(value)) \(unit)")
        }
    }

    // MARK: The rows, as a list

    private var rowLists: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            ForEach(model.visibleRows, id: \.self) { kind in
                rowEditor(kind)
            }
        }
    }

    private func rowEditor(_ kind: LayoutEditorModel.RowKind) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionHeader(title: kind.title)
            Card {
                VStack(spacing: Theme.Space.xs) {
                    if model.row(kind).isEmpty {
                        Text("No keys here.")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.Text.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(model.row(kind)) { slot in
                        keyRow(slot, in: kind)
                    }
                }
            }
        }
    }

    private func keyRow(_ slot: SlotSpec, in kind: LayoutEditorModel.RowKind) -> some View {
        let keys = model.row(kind)
        let position = (keys.firstIndex(of: slot) ?? 0) + 1
        return HStack(spacing: Theme.Space.sm) {
            Button {
                model.selection = model.selection?.id == slot.id ? nil : slot
            } label: {
                HStack(spacing: Theme.Space.xs) {
                    slotGlyph(slot.action).frame(width: 22)
                    Text(slot.action.title)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.Text.primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(Self.widthLabel(slot.width))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.Text.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(slot.action.title), key \(position) of \(keys.count)")
            .accessibilityValue(Self.widthLabel(slot.width))
            .accessibilityHint("Opens this key's settings")

            // **Not only a drag.** These two buttons are the whole reason a
            // VoiceOver user can rearrange the keyboard at all.
            Button {
                model.move(slot, by: -1)
            } label: {
                Image(systemName: "arrow.left").font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(position == 1 ? Theme.Text.tertiary : Theme.Brand.solid)
            .disabled(position == 1)
            .accessibilityLabel("Move \(slot.action.title) left")

            Button {
                model.move(slot, by: 1)
            } label: {
                Image(systemName: "arrow.right").font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(position == keys.count ? Theme.Text.tertiary : Theme.Brand.solid)
            .disabled(position == keys.count)
            .accessibilityLabel("Move \(slot.action.title) right")
        }
        .accessibilityIdentifier("slot-\(slot.action.title)")
    }

    static func widthLabel(_ width: SlotWidth) -> String {
        switch width {
        case .fill: return "Fill"
        case .units(let value): return String(format: "%.1fx", value)
        }
    }

    @ViewBuilder
    private func slotGlyph(_ action: SlotAction) -> some View {
        if let glyph = action.glyph {
            Image(systemName: glyph)
                .font(.system(size: 15))
                .foregroundStyle(Theme.Text.secondary)
        } else {
            Text(action.title.prefix(3))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.Text.secondary)
        }
    }

    // MARK: Inspector

    private func keyInspector(_ slot: SlotSpec) -> some View {
        let verdict = model.canRemove(slot)
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack {
                SectionHeader(title: slot.action.title)
                Spacer()
                Button("Done") { model.selection = nil }
                    .font(.system(size: 13, weight: .semibold))
                    .accessibilityIdentifier("inspector-done")
            }
            Card {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    widthControl(slot)
                    divider
                    actionPicker(slot)
                    divider
                    HStack {
                        Button("Move left") { model.move(slot, by: -1) }
                        Spacer()
                        Button("Move right") { model.move(slot, by: 1) }
                        Spacer()
                        Button("Remove", role: .destructive) { model.remove(slot) }
                            .disabled(!verdict.isAllowed)
                            .accessibilityIdentifier("inspector-remove")
                    }
                    .font(.system(size: 14))
                    if !verdict.isAllowed {
                        // The refusal names its reason where the disabled button
                        // is, not as an error after the tap.
                        Text(verdict.reason)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.Semantic.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func widthControl(_ slot: SlotSpec) -> some View {
        let isFill = slot.width == .fill
        let units: CGFloat = {
            if case .units(let value) = slot.width { return value }
            return 1
        }()
        return VStack(alignment: .leading, spacing: 4) {
            Toggle(
                "Fill the row",
                isOn: Binding(
                    get: { isFill },
                    set: { model.setWidth($0 ? .fill : .units(units), for: slot) })
            )
            .font(.system(size: 15))
            .accessibilityIdentifier("inspector-fill")
            if !isFill {
                slider(
                    "Width", value: units,
                    range: SlotWidth.minimumUnits...SlotWidth.maximumUnits, unit: "x",
                    identifier: "inspector-width"
                ) { model.setWidth(.units($0), for: slot) }
            }
        }
    }

    private func actionPicker(_ slot: SlotSpec) -> some View {
        let kind = model.rowKind(of: slot) ?? .bottom
        let options = model.catalogue(for: kind)
        // The key's own action is always offered, even when it is not in the
        // catalogue for its row: the space bar is not addable and must still be
        // selectable, or opening the picker on it silently retargets it.
        let all = options.contains(slot.action) ? options : [slot.action] + options
        return Picker(
            "Action",
            selection: Binding(
                get: { slot.action },
                set: { model.setAction($0, for: slot) })
        ) {
            ForEach(all, id: \.self) { action in
                Text(action.title).tag(action)
            }
        }
        .font(.system(size: 15))
        .accessibilityIdentifier("inspector-action")
    }

    // MARK: Add

    private var addDrawer: some View {
        let target = model.selection.flatMap { model.rowKind(of: $0) } ?? .bottom
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionHeader(title: "Add a key")
            Card {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    Text("Adds to the \(target.title.lowercased()).")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Text.secondary)
                    FlowRow(spacing: Theme.Space.xs) {
                        ForEach(model.catalogue(for: target), id: \.self) { action in
                            Button {
                                model.add(action, to: target)
                            } label: {
                                HStack(spacing: 4) {
                                    slotGlyph(action)
                                    Text(action.title)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(Theme.Text.primary)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(Theme.Surface.raised))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("add-\(action.title)")
                            .accessibilityLabel("Add \(action.title)")
                        }
                    }
                }
            }
        }
    }

    // MARK: Problems

    @ViewBuilder
    private var problems: some View {
        let issues = model.issues
        if !issues.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                SectionHeader(title: "Problems")
                Card {
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        ForEach(issues) { issue in
                            HStack(alignment: .top, spacing: Theme.Space.xs) {
                                Image(
                                    systemName: issue.severity == .error
                                        ? "exclamationmark.triangle.fill" : "info.circle"
                                )
                                .foregroundStyle(
                                    issue.severity == .error
                                        ? Theme.Semantic.record : Theme.Semantic.warning)
                                Text(issue.message)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.Text.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
            }
            .accessibilityIdentifier("layout-problems")
        }
    }

    private var divider: some View {
        Divider().overlay(Theme.Surface.separator)
    }
}

// MARK: - Thumbnail

/// A wireframe of a layout, small enough to compare five of them at a glance.
///
/// Drawn from the layout rather than from an asset, so a preset cannot end up
/// with a picture that no longer matches it.
struct LayoutThumbnail: View {
    let layout: KeyboardCustomization

    var body: some View {
        GeometryReader { geo in
            let gap: CGFloat = 2
            let rows = CGFloat(layout.rowCount)
            let height = max(2, (geo.size.height - gap * (rows - 1)) / rows)
            VStack(spacing: gap) {
                if layout.showsNumberRow { bar(count: 10, height: height) }
                bar(count: 10, height: height)
                bar(count: 9, height: height)
                bar(count: 9, height: height)
                bar(count: layout.bottomRow.count, height: height)
                if !layout.cursorRow.isEmpty { bar(count: layout.cursorRow.count, height: height) }
            }
            .frame(width: geo.size.width * layout.geometry.reach.widthFraction)
            .frame(maxWidth: .infinity, alignment: alignment)
            // Pinned for the same reason `KeyboardView.reachAlignment` is:
            // `.leading` resolves against the ambient layout direction, so on a
            // Hebrew system a thumbnail for `.left` reach would hug the physical
            // right edge. Not reachable today, because every shipped preset is
            // `.full` — one preset away from being the seventh time this repo
            // mirrored something that should not mirror.
            .environment(\.layoutDirection, .leftToRight)
        }
        .accessibilityHidden(true)
    }

    private var alignment: Alignment {
        switch layout.geometry.reach {
        case .full: return .center
        case .left: return .leading
        case .right: return .trailing
        }
    }

    private func bar(count: Int, height: CGFloat) -> some View {
        HStack(spacing: 1.5) {
            ForEach(0..<max(1, count), id: \.self) { _ in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Theme.Text.secondary.opacity(0.35))
            }
        }
        .frame(height: height)
    }
}
