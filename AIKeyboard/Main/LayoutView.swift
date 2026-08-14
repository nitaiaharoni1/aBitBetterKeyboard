import SwiftUI
import AIKeyboardCore

/// The layout editor: the real keyboard, a tray of unused keys, a slim
/// dock for the selected key, and Options.
///
/// **The canvas is the real `KeyboardView`.** Nothing here redraws the keyboard
/// for editing, so what the user arranges is literally what they get.
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
    /// Keys tab body evaluation. Constructing a `KeyboardController` there
    /// meant a fresh Combine subscription to `ScreenContextSession.shared` and a
    /// full `UITextChecker` pass through `refreshSuggestions()` on every render of
    /// the Keys tab — and tapping Done writes to the store, which
    /// re-renders that tab, which builds another one. The app hung hard enough
    /// that four UI tests timed out without leaving a crash report.
    @StateObject private var model = LayoutEditorModel(layout: .default)
    @StateObject private var canvas = KeyboardController(
        target: MockTextTarget(), language: .english)

    @State private var hasLoaded = false
    @State private var keyFrames: [UUID: CGRect] = [:]
    @State private var frozenBands: [ClosedRange<CGFloat>] = []
    @State private var dragLocation: CGPoint = .zero
    @State private var keyboardGlobal: CGRect = .zero
    @State private var trayHeight: CGFloat = 160
    @State private var showOptions = false
    @State private var resizeStartPixels: CGFloat = 0

    /// **Takes nothing, and that is the fix for a hang.**
    ///
    /// It used to be `LayoutView(layout: store.keyboardLayout)`. A
    /// `NavigationLink` destination inside a `ScrollView` is rebuilt on every
    /// Keys tab body evaluation, and reading the store there made the
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
                if let slot = model.selection, model.session == nil {
                    LayoutKeyInspectorSection(model: model, slot: slot)
                        .padding(.horizontal, Theme.Space.md)
                        .padding(.vertical, Theme.Space.sm)
                }
                LayoutTray(
                    model: model,
                    keyboardGlobal: keyboardGlobal,
                    geometry: canvasGeometry,
                    dragLocation: $dragLocation,
                    trayHeight: $trayHeight
                )
                if !model.issues.isEmpty {
                    LayoutProblemsSection(model: model)
                        .padding(.horizontal, Theme.Space.md)
                        .padding(.vertical, Theme.Space.sm)
                }
            }
        }
        .navigationTitle("Keyboard layout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    model.undo()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .disabled(!model.canUndo || model.session != nil || model.resize != nil)
                .accessibilityIdentifier("layout-undo")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Options") { showOptions = true }
                    .disabled(model.session != nil || model.resize != nil)
                    .accessibilityIdentifier("layout-options")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    store.keyboardLayout = model.draft
                    dismiss()
                }
                .fontWeight(.semibold)
                .disabled(!model.isUsable || model.session != nil || model.resize != nil)
                .accessibilityIdentifier("layout-done")
            }
        }
        .onChange(of: model.draft) { _, _ in applyCanvas() }
        .onChange(of: model.session) { _, _ in applyCanvas() }
        .onChange(of: model.resize) { _, _ in applyCanvas() }
        .sheet(isPresented: $showOptions) {
            LayoutOptionsSheet(model: model)
        }
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            let initialLayout = store.storedKeyboardLayout
            model.draft = initialLayout
            applyCanvas()
        }
    }

    // MARK: Canvas

    private var canvasSection: some View {
        KeyboardView(controller: canvas, isEditingLayout: true)
            .allowsHitTesting(false)
            .background {
                GeometryReader { geo in
                    Color.clear.preference(
                        key: LayoutChromeFrameKey.self,
                        value: geo.frame(in: .global))
                }
            }
            .onPreferenceChange(KeyFramesKey.self) { frames in
                keyFrames = Self.mapFrames(frames, to: editableSlots)
                frozenBands = Self.frozenBands(from: frames)
            }
            .onPreferenceChange(LayoutChromeFrameKey.self) { frame in
                keyboardGlobal = frame
            }
            .overlay { selectionOverlay }
            .background(Theme.Keys.background)
    }

    private var editableSlots: [SlotSpec] {
        model.displayed.bottomRow + model.displayed.cursorRow
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

    private var canvasGeometry: CanvasGeometry {
        var bands: [LayoutEditorModel.RowKind: ClosedRange<CGFloat>] = [:]
        if let band = band(for: model.displayed.cursorRow) { bands[.cursor] = band }
        if let band = band(for: model.displayed.bottomRow) { bands[.bottom] = band }
        let height = keyboardGlobal.height
        return CanvasGeometry(
            keyFrames: keyFrames,
            rowBands: bands,
            trayBand: height > 0 ? height...(height + max(trayHeight, 80)) : nil,
            extraRowWell: extraRowWell,
            frozenBands: frozenBands
        )
    }

    /// The extra row draws at the top of the letter block, so the well *is*
    /// that top frozen row. A reconstructed box above it flip-flops: the row
    /// appears under the finger, the well vanishes, the hit misses.
    private var extraRowWell: ClosedRange<CGFloat>? {
        guard model.displayed.cursorRow.isEmpty else { return nil }
        return frozenBands.min(by: { $0.lowerBound < $1.lowerBound })
    }

    /// Compiled letter, digit, shift and delete keys have no `#uuid` suffix.
    /// Those rows are not the user's to rearrange.
    static func frozenBands(from frames: [String: CGRect]) -> [ClosedRange<CGFloat>] {
        var rows: [ClosedRange<CGFloat>] = []
        for (id, rect) in frames where !id.contains("#") {
            let band = rect.minY...rect.maxY
            if let index = rows.firstIndex(where: {
                $0.lowerBound <= band.upperBound && band.lowerBound <= $0.upperBound
            }) {
                let merged = rows[index]
                rows[index] =
                    min(merged.lowerBound, band.lowerBound)...max(merged.upperBound, band.upperBound)
            } else {
                rows.append(band)
            }
        }
        return rows
    }

    private func band(for slots: [SlotSpec]) -> ClosedRange<CGFloat>? {
        let lifted = model.session?.lifted.id
        let frames = slots.filter { $0.id != lifted }.compactMap { keyFrames[$0.id] }
        guard let minY = frames.map(\.minY).min(), let maxY = frames.map(\.maxY).max()
        else { return nil }
        return (minY - 6)...(maxY + 6)
    }

    private var selectionOverlay: some View {
        ZStack(alignment: .topLeading) {
            ForEach(editableSlots) { slot in
                if let frame = keyFrames[slot.id] {
                    overlayKey(slot, frame: frame)
                }
            }

            if let session = model.session {
                let frame = keyFrames[session.lifted.id]
                let origin = frame.map { CGPoint(x: $0.midX, y: $0.midY) } ?? .zero
                RoundedRectangle(cornerRadius: Theme.Radius.key, style: .continuous)
                    .fill(Theme.Brand.solid.opacity(0.3))
                    .frame(width: frame?.width ?? 44, height: frame?.height ?? 44)
                    .position(dragLocation == .zero ? origin : dragLocation)
                    .allowsHitTesting(false)
            }

            if let slot = handleSlot, model.session == nil,
                model.canResize(slot), let frame = keyFrames[slot.id]
            {
                resizeHandle(for: slot, frame: frame)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func overlayKey(_ slot: SlotSpec, frame: CGRect) -> some View {
        let lifted = model.session?.lifted.id == slot.id
        let actions = model.accessibilityActions(for: slot)
        return Color.clear
            .contentShape(Rectangle())
            .frame(width: frame.width, height: frame.height)
            .overlay {
                if model.selection?.id == slot.id {
                    RoundedRectangle(cornerRadius: Theme.Radius.key, style: .continuous)
                        .strokeBorder(Theme.Brand.solid, lineWidth: 2)
                }
            }
            .overlay(alignment: .topTrailing) {
                if model.canRemove(slot).isAllowed, model.session == nil {
                    Button {
                        model.perform(.remove, on: slot)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(Theme.Text.onBrand, Theme.Semantic.record)
                    }
                    .offset(x: 6, y: -6)
                    .accessibilityIdentifier("remove-\(slot.action.title)")
                    .accessibilityLabel("Remove \(slot.action.title)")
                }
            }
            .opacity(lifted ? 0 : 1)
            .position(x: frame.midX, y: frame.midY)
            .onTapGesture {
                if let id = model.resize?.slotID { model.endResize(for: id) }
                model.selection = slot
            }
            .gesture(boardDrag(slot))
            .accessibilityElement()
            .accessibilityLabel(accessibilityLabel(for: slot))
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("canvas-\(slot.action.title)")
            .accessibilityActions {
                ForEach(actions, id: \.self) { action in
                    Button(action.title) { model.perform(action, on: slot) }
                }
            }
    }

    private func accessibilityLabel(for slot: SlotSpec) -> String {
        let layout = model.displayed
        let kind: LayoutEditorModel.RowKind? =
            layout.bottomRow.contains(where: { $0.id == slot.id })
            ? .bottom
            : layout.cursorRow.contains(where: { $0.id == slot.id }) ? .cursor : nil
        guard let kind else { return slot.action.title }
        let keys = kind == .bottom ? layout.bottomRow : layout.cursorRow
        let position = (keys.firstIndex(where: { $0.id == slot.id }) ?? 0) + 1
        return "\(slot.action.title), key \(position) of \(keys.count), \(kind.title)"
    }

    /// The handle stays mounted on the key being resized, even if selection
    /// moves, so SwiftUI cannot tear the gesture down and leave `resize` stuck.
    private var handleSlot: SlotSpec? {
        if let resize = model.resize {
            return editableSlots.first { $0.id == resize.slotID } ?? model.selection
        }
        return model.selection
    }

    private var letterUnit: CGFloat {
        let total = keyboardGlobal.width
        let grid = total * model.displayed.geometry.reach.widthFraction
        return KeyboardLayout.unitWidth(
            totalWidth: grid,
            spacing: Theme.Metrics.keySpacing,
            sideInset: Theme.Metrics.sideInset
        )
    }

    private func resizeHandle(for slot: SlotSpec, frame: CGRect) -> some View {
        Capsule(style: .continuous)
            .fill(Theme.Brand.solid)
            .frame(width: 5, height: 22)
            .shadow(color: Theme.Brand.solid.opacity(0.35), radius: 3, y: 1)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .position(x: frame.maxX - 2, y: frame.midY)
            .id(slot.id)
            .gesture(resizeDrag(slot))
            .accessibilityElement()
            .accessibilityLabel("Resize \(slot.action.title)")
            .accessibilityIdentifier("resize-\(slot.action.title)")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: model.perform(.widen, on: slot)
                case .decrement: model.perform(.narrow, on: slot)
                @unknown default: break
                }
            }
    }

    private func resizeDrag(_ slot: SlotSpec) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                if model.resize == nil {
                    resizeStartPixels = keyFrames[slot.id]?.width ?? resizeStartPixels
                    model.beginResize(slot)
                    Feedback.modifierPress()
                }
                guard model.resize?.slotID == slot.id else { return }
                let next = SlotWidth.proposed(
                    start: model.resize?.start ?? slot.width,
                    startPixels: resizeStartPixels,
                    translation: value.translation.width,
                    unit: letterUnit
                )
                let before = model.resize?.proposed
                model.updateResize(next)
                if model.resize?.proposed != before { Feedback.modifierPress() }
            }
            .onEnded { _ in
                let before = model.draft
                model.endResize(for: slot.id)
                if model.draft != before { Feedback.success() }
            }
    }

    private func boardDrag(_ slot: SlotSpec) -> some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .onChanged { value in
                if model.session == nil {
                    model.beginDrag(slot)
                    Feedback.modifierPress()
                }
                guard model.session?.lifted.id == slot.id else { return }
                let point = CGPoint(
                    x: value.location.x - keyboardGlobal.minX,
                    y: value.location.y - keyboardGlobal.minY
                )
                dragLocation = point
                model.updateDrag(at: point, in: canvasGeometry)
            }
            .onEnded { _ in
                let before = model.draft
                model.endDrag(for: slot.id)
                dragLocation = .zero
                if model.draft != before { Feedback.success() }
            }
    }

    private func applyCanvas() {
        canvas.apply(model.displayed, allowingIncomplete: true)
    }
}

// MARK: - Overlay helpers

private struct LayoutChromeFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private struct LayoutTray: View {
    @ObservedObject var model: LayoutEditorModel
    let keyboardGlobal: CGRect
    let geometry: CanvasGeometry
    @Binding var dragLocation: CGPoint
    @Binding var trayHeight: CGFloat
    @State private var liftIDs: [SlotAction: UUID] = [:]
    @State private var trayWidth: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Divider.themed
            SectionHeader(title: "Unused keys")
                .padding(.horizontal, Theme.Space.md)
            VStack(alignment: .leading, spacing: model.displayed.geometry.rowSpacing) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: Theme.Metrics.keySpacing) {
                        ForEach(row) { item in
                            trayChip(item)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.horizontal, Theme.Metrics.sideInset)
            .padding(.bottom, Theme.Space.sm)
        }
        .background(Theme.Keys.background)
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        trayHeight = geo.size.height
                        trayWidth = geo.size.width
                    }
                    .onChange(of: geo.size) { _, size in
                        trayHeight = size.height
                        trayWidth = size.width
                    }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var keyHeight: CGFloat { model.displayed.geometry.keyHeight }

    /// One letter-key wide, using the same arithmetic as `KeyboardView`.
    private var keyWidth: CGFloat {
        let total = keyboardGlobal.width > 0 ? keyboardGlobal.width : trayWidth
        let gridWidth = total * model.displayed.geometry.reach.widthFraction
        return KeyboardLayout.unitWidth(
            totalWidth: gridWidth,
            spacing: Theme.Metrics.keySpacing,
            sideInset: Theme.Metrics.sideInset
        )
    }

    private var rows: [[TrayItem]] {
        let inner = max(trayWidth - Theme.Metrics.sideInset * 2, keyWidth)
        let columns = max(1, Int((inner + Theme.Metrics.keySpacing) / (keyWidth + Theme.Metrics.keySpacing)))
        return stride(from: 0, to: model.tray.count, by: columns).map { start in
            Array(model.tray[start..<min(start + columns, model.tray.count)])
        }
    }

    private func trayChip(_ item: TrayItem) -> some View {
        let actions = model.trayActions(for: item.action)
        let spec = KeyboardLayout.previewKey(for: item.action)
        return Group {
            if let spec {
                KeyView(
                    spec: spec,
                    width: keyWidth,
                    height: keyHeight,
                    language: .english,
                    shift: .off,
                    showsActionCaption: item.action != .emoji && item.action != .dictation,
                    usesNeutralActionTint: true,
                    onPress: { _, _ in }
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .frame(width: keyWidth, height: keyHeight)
        .opacity(isHeld(item) ? 0.35 : 1)
        .contentShape(Rectangle())
        .onTapGesture {
            guard model.resize == nil, !isHeld(item),
                model.canAccept(item.action, in: .bottom)
            else { return }
            model.add(item.action, to: .bottom)
        }
        .gesture(trayDrag(item.action))
        .accessibilityElement()
        .accessibilityLabel("Add \(item.action.title)")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("add-\(item.action.title)")
        .accessibilityActions {
            ForEach(actions, id: \.self) { action in
                Button(action.title) { model.perform(action, adding: item.action) }
            }
        }
    }

    private func isHeld(_ item: TrayItem) -> Bool {
        guard let session = model.session, case .tray(let action) = session.origin else {
            return false
        }
        return action == item.action
    }

    private func trayDrag(_ action: SlotAction) -> some Gesture {
        LongPressGesture(minimumDuration: 0.2)
            .sequenced(
                before: DragGesture(minimumDistance: 0, coordinateSpace: .global)
            )
            .onChanged { value in
                guard case .second(true, let drag?) = value else { return }
                if model.session == nil, let id = model.beginDragFromTray(action) {
                    liftIDs[action] = id
                    Feedback.modifierPress()
                }
                guard liftIDs[action] != nil, model.session?.lifted.id == liftIDs[action]
                else { return }
                let point = CGPoint(
                    x: drag.location.x - keyboardGlobal.minX,
                    y: drag.location.y - keyboardGlobal.minY
                )
                dragLocation = point
                model.updateDrag(at: point, in: geometry)
            }
            .onEnded { _ in
                let before = model.draft
                if let id = liftIDs[action] {
                    model.endDrag(for: id)
                    liftIDs[action] = nil
                }
                dragLocation = .zero
                if model.draft != before { Feedback.success() }
            }
    }
}

private struct LayoutOptionsSheet: View {
    @ObservedObject var model: LayoutEditorModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    LayoutPresetSection(model: model)
                    LayoutGeometrySection(model: model)
                    barEnds
                }
                .padding(.horizontal, Theme.Space.md)
                .padding(.vertical, Theme.Space.md)
            }
            .background(Theme.Surface.background.ignoresSafeArea())
            .navigationTitle("Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("layout-options-done")
                }
            }
        }
    }

    private var barEnds: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            SectionHeader(title: "Suggestion bar")
            barGroup("Leading", kind: .barLeading)
            barGroup("Trailing", kind: .barTrailing)
        }
    }

    private func barGroup(_ title: String, kind: LayoutEditorModel.RowKind) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(title)
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Text.secondary)
            if !model.row(kind).isEmpty {
                ForEach(model.row(kind)) { slot in
                    HStack {
                        SlotGlyphView(action: slot.action)
                        Text(slot.action.title)
                            .font(Theme.Fonts.body)
                            .foregroundStyle(Theme.Text.primary)
                        Spacer()
                        if model.accessibilityActions(for: slot).contains(.remove) {
                            Button("Remove") { model.perform(.remove, on: slot) }
                                .font(Theme.Fonts.caption)
                                .foregroundStyle(Theme.Semantic.record)
                        }
                    }
                }
            }
            FlowRow(spacing: Theme.Space.xs) {
                ForEach(SuggestionBar.barCatalogue, id: \.self) { action in
                    Button {
                        model.add(action, to: kind)
                    } label: {
                        HStack(spacing: Theme.Space.xxs) {
                            SlotGlyphView(action: action)
                            Text(action.title)
                                .font(Theme.Fonts.micro)
                                .foregroundStyle(Theme.Text.primary)
                        }
                        .padding(.horizontal, Theme.Space.sm)
                        .padding(.vertical, Theme.Space.xs)
                        .background(Capsule().fill(Theme.Surface.background))
                        .overlay(Capsule().strokeBorder(Theme.Surface.separator, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("add-\(action.title)")
                    .accessibilityLabel("Add \(action.title)")
                }
            }
        }
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
