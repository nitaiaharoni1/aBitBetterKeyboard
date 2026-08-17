import SwiftUI
import AIKeyboardCore

/// The layout editor: a workbench, a shelf, and the real keyboard pinned to the
/// bottom of the screen where a keyboard lives.
///
/// **The canvas is the real `KeyboardView`.** Nothing here redraws the keyboard
/// for editing, so what the user arranges is literally what they get.
///
/// **The keys never move, and everything about the composition follows from
/// that.** The canvas is the bottom safe-area inset, so it is the one fixed
/// thing on the screen; the shelf above it (problems, the selected key, the
/// spare keys) grows upward into the workbench rather than shunting the
/// keyboard down. That is also why the settings are here rather than behind an
/// Options sheet: key height, row spacing and the number row are settings whose
/// entire subject is what the keyboard looks like, and a sheet covered the
/// keyboard while you dragged the slider that changed it.
struct LayoutView: View {

    @EnvironmentObject private var store: SharedStore
    @Environment(AppChrome.self) private var chrome
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    /// Measured for `FullAccessNeededBanner`: without Full Access every edit
    /// made below is stored and never reaches the keyboard, which goes on
    /// drawing the shipped default. Re-read on every return to the
    /// foreground, the same as `LanguagesView`, because the switch is thrown
    /// in Settings and nothing notifies the app.
    @State private var setup = SetupState()

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
    @State private var trayGlobal: CGRect = .zero
    @State private var resizeStartPixels: CGFloat = 0

    /// The screen's own box, below the nav bar — everything `workbench` and
    /// `shelf` have to fit inside once the canvas claims its `safeAreaInset`.
    /// Measured, not assumed, by `LayoutViewportHeightKey` on the root
    /// `ZStack`, the same `.background { GeometryReader { … } }` idiom
    /// `keyboardGlobal` already uses below. Starts at 0 so the very first
    /// layout pass — before any measurement has arrived — reads as "no room"
    /// and `hasRoomForWorkbenchFloor` defaults to the safe answer rather than
    /// briefly forcing a floor it has not checked for.
    @State private var availableHeight: CGFloat = 0

    /// `shelf`'s own real height, measured the same way, because its pieces
    /// are fixed (`contextBandHeight` and the tray) but `LayoutProblemsSection`
    /// is not — an unbounded number of wrapped warning lines is exactly the
    /// part `keyAreaHeight`'s arithmetic cannot predict, so this is read off
    /// the rendered view rather than recomputed.
    @State private var shelfHeight: CGFloat = 0

    /// The shelf's middle band. Fixed, because a live drag and the
    /// selected-key inspector take turns in it and a band that resized would
    /// shunt the spare keys under the thumb that was reaching for them. It is
    /// dropped entirely while neither is happening: the resting hint is
    /// `canvasHint` now, under the keyboard.
    ///
    /// 60 is the floor rather than a taste: the inspector's controls are 44 pt
    /// targets inside `Theme.Space.xs` of padding, and anything less clips them.
    private static let contextBandHeight: CGFloat = 60

    /// The workbench's floor when there is room for one, so a tall preset
    /// cannot squeeze it away.
    ///
    /// **The canvas is a `safeAreaInset`, so it claims its height first and
    /// `workbench` — the flexible half, being a `ScrollView` — absorbs whatever
    /// the shelf below it leaves over.** The shelf's own pieces are mostly
    /// fixed (`contextBandHeight` above, and the tray drawn at the row height
    /// the key is about to become), so on Roomy with the number row on, on an
    /// iPhone SE, the canvas alone claims 426 of the 603 pt below the nav bar
    /// and the shelf claims another ~167, leaving the workbench about 10 pt —
    /// the preset cards and the sliders that would get the user back out of
    /// Roomy are still there, just not reachable.
    ///
    /// **138 is not a round number: it is what the workbench gets on the
    /// untouched *default* layout on the same phone**, so no combination of
    /// presets and sliders ever leaves the workbench worse off than the keyboard
    /// as it ships. It is also enough to see the Presets header and at least the
    /// top of the first preset card, which is the one control that gets a user
    /// out of any preset they regret.
    ///
    /// **Applied only when `hasRoomForWorkbenchFloor` says there is room for
    /// it.** `contextBand` and the tray are exact `.frame(height:)`, not a
    /// range, so the shelf cannot actually shrink to make way — a floor forced
    /// on regardless would push the outer stack past what the screen holds,
    /// which on the single most extreme device-and-preset combination could
    /// carry the tray under the canvas. That is the same defect this floor
    /// exists to fix, wearing the tray's clothes instead of the workbench's.
    /// So this is a ceiling on how generous the floor gets to be, never a
    /// guarantee: when there is not enough room, `workbench` takes what is
    /// left, exactly as it did before this existed.
    private static let workbenchMinHeight: CGFloat = 138

    /// `canvasHint`'s whole band: a 1 pt rule and a 20 pt line of 10 pt text.
    /// Small on purpose — it is a caption under the keyboard, not a row of it.
    private static let canvasHintHeight: CGFloat = 21

    /// What `canvasSection` claims from the bottom of the screen right now —
    /// the keyboard's own height plus `canvasHint` — computed rather
    /// than measured: `Theme.Metrics.totalHeight(for:showsBanner:)` is the
    /// same formula `KeyboardViewController` uses, so this can never disagree
    /// with what `canvasSection` renders, and it is available before the
    /// canvas has laid out even once — unlike `shelfHeight`, nothing here
    /// varies with content the formula cannot see. `model.displayed` rather
    /// than `model.draft`: mid-drag or mid-resize the *displayed* geometry is
    /// what `canvasSection` is actually drawing.
    private var canvasHeight: CGFloat {
        Theme.Metrics.totalHeight(for: model.displayed, showsBanner: false)
            + Self.canvasHintHeight
    }

    /// Whether `workbenchMinHeight` fits without pushing the outer stack past
    /// the screen. See that constant's note for why this exists at all.
    private var hasRoomForWorkbenchFloor: Bool {
        availableHeight - canvasHeight - shelfHeight >= Self.workbenchMinHeight
    }

    /// What `FullAccessNeededBanner` says here. Mirrors
    /// `SetupState.languagesNeedFullAccess`'s hedge deliberately: `setup
    /// .fullAccess` can only ever *confirm* a yes, so this says "once Full
    /// Access is on" rather than asserting it is off right now.
    private static let fullAccessMessage =
        "The keyboard can only read this layout once Full Access is on. Until then it draws the "
        + "shipped default, whatever you build here. Done still saves it, ready for when Full "
        + "Access catches up."

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
                workbench
                shelf
            }
        }
        // Measures the box below the nav bar, before the canvas's own
        // `safeAreaInset` is chained on below — see `availableHeight`.
        .background {
            GeometryReader { geo in
                Color.clear.preference(
                    key: LayoutViewportHeightKey.self, value: geo.size.height)
            }
        }
        .onPreferenceChange(LayoutViewportHeightKey.self) { availableHeight = $0 }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            canvasSection
        }
        .navigationTitle("Layout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    model.undo()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .disabled(!model.canUndo || model.session != nil || model.resize != nil)
                .accessibilityIdentifier("layout-undo")
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
        // The app's tab bar is a `safeAreaInset`, not a `TabView`'s, so
        // `.toolbar(.hidden, for: .tabBar)` cannot reach it. See `AppChrome`.
        .onAppear {
            chrome.hidesTabBar = true
            setup = .current(store: store)
        }
        .onDisappear { chrome.hidesTabBar = false }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { setup = .current(store: store) }
        }
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            let initialLayout = store.storedKeyboardLayout
            model.draft = initialLayout
            applyCanvas()
        }
    }

    // MARK: Workbench

    /// Everything that is a choice rather than a gesture. It scrolls, because on
    /// a short phone with a tall keyboard there is not room for all of it, and it
    /// is the half of the screen that can afford to be shorter.
    private var workbench: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                // First in the stack, ahead of the controls it is warning
                // about, so it is what a squeezed `workbenchMinHeight`
                // viewport shows before anything else on a short phone.
                if setup.fullAccess != .confirmed {
                    FullAccessNeededBanner(message: Self.fullAccessMessage, context: "layout")
                }
                LayoutPresetSection(model: model)
                LayoutGeometrySection(model: model)
            }
            .padding(.horizontal, Theme.Space.md)
            .padding(.top, Theme.Space.md)
            .padding(.bottom, Theme.Space.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Deselecting by tapping the empty canvas used to be the only route
            // out of the inspector; the controls inside claim their own taps
            // first, so this only fires on the gaps between them.
            .contentShape(Rectangle())
            .onTapGesture(perform: deselect)
        }
        .frame(minHeight: hasRoomForWorkbenchFloor ? Self.workbenchMinHeight : 0)
    }

    // MARK: Shelf

    /// What is wrong, what is selected, and the keys that are not on the board —
    /// on the keyboard's own surface, directly above it.
    ///
    /// **The hairline is not decoration.** `Surface.background` and
    /// `Keys.background` are two different colours in light appearance and the
    /// *same* colour in dark, so without a rule the shelf and the workbench are
    /// one undifferentiated field at night.
    private var shelf: some View {
        VStack(spacing: Theme.Space.xs) {
            if !model.issues.isEmpty {
                LayoutProblemsSection(model: model)
                    .padding(.horizontal, Theme.Space.md)
            }
            // Dropped from the stack rather than drawn empty when neither a
            // drag nor a selection has anything to say: the resting hint moved
            // under the keyboard (`canvasHint`), and a 60 pt hole above SPARE
            // KEYS is the workbench's room being spent on nothing.
            if model.session != nil || model.selection != nil {
                contextBand
            }
            traySection
        }
        .padding(.top, Theme.Space.sm)
        .background {
            Theme.Keys.background
                .overlay(alignment: .top) {
                    Theme.Surface.separator.frame(height: 1)
                }
        }
        // A second `.background`, behind the one above: attaching it here
        // rather than wrapping `shelf`'s content in a `GeometryReader` is
        // what keeps this an observer rather than a layout participant — see
        // `shelfHeight`. `LayoutProblemsSection` is the one part of the total
        // that `hasRoomForWorkbenchFloor`'s formula cannot predict.
        .background {
            GeometryReader { geo in
                Color.clear.preference(key: ShelfHeightKey.self, value: geo.size.height)
            }
        }
        .onPreferenceChange(ShelfHeightKey.self) { shelfHeight = $0 }
    }

    /// One band, two states — the resting hint left it for `canvasHint`, and
    /// the band leaves the shelf with it. The drag state is the only place the editor can
    /// teach the gesture that changed: a key leaves the keyboard by being lifted
    /// *up* into the tray, not dropped off the bottom.
    @ViewBuilder private var contextBand: some View {
        Group {
            if let session = model.session {
                // A key lifted off the board can be put back or thrown away; one
                // lifted out of the tray was never on the board, so offering to
                // take it off would be an instruction to undo the drag.
                switch session.origin {
                case .board:
                    shelfHint(
                        "Drop it on a row, or lift it up to the spare keys to take it off.",
                        icon: "arrow.up")
                case .tray:
                    shelfHint(
                        "Drop it on the action row or the bottom row.",
                        icon: "arrow.down")
                }
            } else if let slot = model.selection {
                // The frame the canvas published for this very key, so the label
                // switch inside can say what the keyboard below is actually
                // drawing rather than what a unit count suggests.
                LayoutKeyInspectorSection(
                    model: model, slot: slot, drawnWidth: keyFrames[slot.id]?.width ?? 0)
            }
        }
        .frame(height: Self.contextBandHeight)
        .padding(.horizontal, Theme.Space.md)
        .animation(Theme.Motion.quick, value: model.selection?.id)
    }

    private func shelfHint(_ text: String, icon: String) -> some View {
        Label {
            Text(text)
                .font(Theme.Fonts.caption)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: icon).font(Theme.Fonts.caption)
        }
        .foregroundStyle(Theme.Keys.secondaryLabel)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Not `layout-hint`: that identifier belongs to the resting legend
        // under the keyboard now, and two elements answering to one name is
        // an ambiguous query rather than a found one.
        .accessibilityIdentifier("layout-drag-hint")
    }

    /// **`Keys.secondaryLabel`, not `Text.tertiary`.** This header sits on the
    /// keyboard's grey, not the app's warm white: the app's tertiary grey lands
    /// at 2.6:1 there, and the keyboard's own secondary label at 4.5:1.
    private var traySection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            HStack(alignment: .firstTextBaseline) {
                Text("SPARE KEYS")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.8)
                Spacer(minLength: Theme.Space.sm)
                Text("Drag one down onto a row")
            }
            .font(Theme.Fonts.micro)
            .foregroundStyle(Theme.Keys.secondaryLabel)
            .padding(.horizontal, Theme.Space.md)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Spare keys. Drag one down onto a row.")

            LayoutTray(
                model: model,
                keyboardGlobal: keyboardGlobal,
                geometry: canvasGeometry,
                dragLocation: $dragLocation,
                trayGlobal: $trayGlobal
            )
        }
    }

    private func deselect() {
        if let id = model.resize?.slotID { model.endResize(for: id) }
        model.selection = nil
    }

    // MARK: Canvas

    /// **Full-bleed, because the real one is.** The editor's whole claim is that
    /// this is the keyboard rather than a picture of it, and an 8 pt gutter down
    /// each side is a picture of it. It also makes the tray's key width the same
    /// arithmetic the keys themselves use, since both divide `keyboardGlobal`.
    private var canvasSection: some View {
        VStack(spacing: 0) {
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
                    keyFrames = LayoutEditorModel.mapFrames(frames, to: editableSlots)
                    frozenBands = LayoutEditorModel.frozenBands(from: frames)
                }
                .onPreferenceChange(LayoutChromeFrameKey.self) { frame in
                    keyboardGlobal = frame
                }
                .overlay { selectionOverlay }
            canvasHint
        }
        .background(Theme.Keys.background.ignoresSafeArea(edges: .bottom))
    }

    /// The one instruction that is true for the whole screen, under the space
    /// row rather than in the shelf's context band.
    ///
    /// **It is a caption on the keyboard, not a row of the keyboard**, so it is
    /// deliberately smaller than anything the shelf draws: it sits below the
    /// last key, where the home indicator's own margin already is, and a line at
    /// shelf size there reads as a sixth key row. The rule above it is the same
    /// hairline the shelf uses, and it is doing the same job — `Keys.background`
    /// runs from the keys straight down past the bottom of the screen, so
    /// without it the sentence floats inside the keyboard rather than under it.
    ///
    /// It stays put through a drag and through a selection: the band above
    /// answers *those* moments, and this is the legend for the screen.
    private var canvasHint: some View {
        VStack(spacing: 0) {
            Theme.Surface.separator.frame(height: 1)
            Text("Tap a key to change it, drag it to move it. The letters stay put.")
                .font(.system(size: 10))
                .foregroundStyle(Theme.Keys.secondaryLabel)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Theme.Space.md)
                .accessibilityIdentifier("layout-hint")
        }
        // Exact rather than intrinsic, so `canvasHeight` can add it without
        // guessing at a line height.
        .frame(height: Self.canvasHintHeight)
    }

    private var editableSlots: [SlotSpec] {
        model.displayed.bottomRow + model.displayed.cursorRow
    }

    private var canvasGeometry: CanvasGeometry {
        var bands: [LayoutEditorModel.RowKind: ClosedRange<CGFloat>] = [:]
        if let band = band(for: model.displayed.cursorRow) { bands[.cursor] = band }
        if let band = band(for: model.displayed.bottomRow) { bands[.bottom] = band }
        // **Negative, and that is correct.** The tray sits above the keyboard
        // now, so its band in keyboard-local coordinates is above the origin —
        // and so is the finger, which `boardDrag` converts the same way.
        let trayBand: ClosedRange<CGFloat>? = {
            guard keyboardGlobal.height > 0, trayGlobal.height > 0 else { return nil }
            let minY = trayGlobal.minY - keyboardGlobal.minY
            let maxY = trayGlobal.maxY - keyboardGlobal.minY
            return minY...maxY
        }()
        return CanvasGeometry(
            keyFrames: keyFrames,
            rowBands: bands,
            trayBand: trayBand,
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

    private func band(for slots: [SlotSpec]) -> ClosedRange<CGFloat>? {
        let lifted = model.session?.lifted.id
        let frames = slots.filter { $0.id != lifted }.compactMap { keyFrames[$0.id] }
        guard let minY = frames.map(\.minY).min(), let maxY = frames.map(\.maxY).max()
        else { return nil }
        return (minY - 6)...(maxY + 6)
    }

    /// **What the user is allowed to touch, said once and quietly.**
    ///
    /// The three letter rows are extracted from Apple's own data for 64
    /// languages and are not the user's to rearrange, and nothing on the screen
    /// said so: the remove badge follows the selection now, so at rest the
    /// editor marked nothing at all and a first-time user spends their first ten
    /// seconds dragging a `Q` that will never move. This is the *static* answer
    /// to the question the deleted home-screen jiggle was the wrong answer to —
    /// a hairline around the two rows that do move, gone the moment a key is
    /// picked up or selected, so it never sits over the thing being judged.
    @ViewBuilder private var editableRowOutlines: some View {
        if model.session == nil, model.selection == nil {
            ForEach([LayoutEditorModel.RowKind.cursor, .bottom], id: \.self) { kind in
                if let frame = rowOutline(kind) {
                    RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                        .strokeBorder(
                            Theme.Brand.solid.opacity(0.65),
                            style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                        )
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    /// The box the row's own keys occupy, loosened by the same 3 pt the keycaps
    /// leave between themselves, so the hairline sits in the gutter rather than
    /// on a cap.
    private func rowOutline(_ kind: LayoutEditorModel.RowKind) -> CGRect? {
        let slots = kind == .bottom ? model.displayed.bottomRow : model.displayed.cursorRow
        let frames = slots.compactMap { keyFrames[$0.id] }
        guard let minX = frames.map(\.minX).min(), let maxX = frames.map(\.maxX).max(),
            let minY = frames.map(\.minY).min(), let maxY = frames.map(\.maxY).max()
        else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            .insetBy(dx: -3, dy: -3)
    }

    private var selectionOverlay: some View {
        ZStack(alignment: .topLeading) {
            editableRowOutlines

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
                if model.canRemove(slot).isAllowed, model.session == nil,
                    model.selection?.id == slot.id
                {
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

private struct LayoutTrayFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

/// Backs `availableHeight`. See `hasRoomForWorkbenchFloor`.
private struct LayoutViewportHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Backs `shelfHeight`. See `hasRoomForWorkbenchFloor`.
private struct ShelfHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct LayoutTray: View {
    @ObservedObject var model: LayoutEditorModel
    let keyboardGlobal: CGRect
    let geometry: CanvasGeometry
    @Binding var dragLocation: CGPoint
    @Binding var trayGlobal: CGRect
    @State private var liftIDs: [SlotAction: UUID] = [:]
    @State private var trayWidth: CGFloat = 0

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Metrics.keySpacing) {
                ForEach(model.tray) { item in
                    trayChip(item)
                }
            }
            .padding(.horizontal, Theme.Space.md)
            .padding(.vertical, Theme.Space.xs)
        }
        .frame(height: keyHeight + Theme.Space.xs * 2)
        // **Off only while a key is in the air**, which is the other half of
        // making this row scroll at all. The catalogue is 23 keys and the row
        // holds about ten, so everything past the screen's right edge was
        // unreachable: each chip's lift gesture was an ordinary `.gesture`, and
        // a SwiftUI gesture on the content beats the scroll view's own pan, so
        // a swipe across the row was swallowed by a long press that then failed.
        // `trayChip` makes that lift simultaneous instead, which leaves exactly
        // one moment where both could act — the press has succeeded and the
        // finger is now carrying a key towards the keyboard — and this is what
        // stops the row sliding out from under that drag.
        .scrollDisabled(model.session != nil)
        .background {
            GeometryReader { geo in
                Color.clear
                    .preference(key: LayoutTrayFrameKey.self, value: geo.frame(in: .global))
                    .onAppear { trayWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, width in trayWidth = width }
            }
        }
        .onPreferenceChange(LayoutTrayFrameKey.self) { trayGlobal = $0 }
        .accessibilityElement(children: .contain)
    }

    /// The bottom row's height, because tapping a chip adds it to the bottom
    /// row: a spare key is drawn the size it is about to become.
    private var keyHeight: CGFloat { model.displayed.geometry.height(.bottom) }

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
                    // The same question the keyboard asks, for the row a tap
                    // would add this key to. It used to be a hand-copied version
                    // of the *action* row's rule, which drifted the moment the
                    // width floor moved: a spare key is one letter wide, so the
                    // answer is no either way, and a second copy of the rule was
                    // only ever a chance to disagree with the real one.
                    showsActionCaption: spec.showsActionCaption(
                        inRow: KeyboardLayout.RowID.bottom, width: keyWidth),
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
        // Simultaneous, not exclusive: see `scrollDisabled` above. A swipe that
        // moves before the 0.2s press has landed fails the press and is left to
        // the scroll view; one that waits takes the key out of the row.
        .simultaneousGesture(trayDrag(item.action))
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
    .environment(AppChrome())
}

#endif
