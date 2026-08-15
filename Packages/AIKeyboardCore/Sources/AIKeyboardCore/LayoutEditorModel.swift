import Combine
import CoreGraphics
import Foundation

/// Where a lift started. Tray origins mint a `SlotSpec` for the session only.
public enum DragOrigin: Equatable, Sendable {
    case board(SlotSpec)
    case tray(SlotAction)
}

/// Where the finger currently proposes to drop.
///
/// `.board` index is into the row *without* the lifted key — the same contract
/// as `move(_:to:at:)`.
public enum DropTarget: Equatable, Sendable {
    case board(row: LayoutEditorModel.RowKind, index: Int)
    case tray
}

public struct DragSession: Equatable, Sendable {
    public let origin: DragOrigin
    public let lifted: SlotSpec
    /// Where the key returns if the gesture ends with no legal target.
    /// Captured at lift so a torn-down board drag cannot fall into the tray.
    public let home: DropTarget
    public var proposed: DropTarget?
    /// After a re-order, `updateDrag` refuses to resolve until a new
    /// `CanvasGeometry` arrives. Re-ordering moves the frames that decide
    /// re-ordering.
    public var awaitingGeometry: Bool
}

/// An in-flight handle drag. `draft` stays put until `endResize`.
public struct ResizeSession: Equatable, Sendable {
    public let slotID: UUID
    public let start: SlotWidth
    public var proposed: SlotWidth
}

/// What the view measured, in the keyboard's own bounds.
///
/// Letter rows (and digits, shift, delete) live in `frozenBands`. A drop there
/// is ignored unless it is also in `extraRowWell`. They are not in `rowBands`.
/// `extraRowWell` is the top frozen row, present only when `cursorRow` is empty.
public struct CanvasGeometry: Equatable, Sendable {
    public var keyFrames: [UUID: CGRect]
    public var rowBands: [LayoutEditorModel.RowKind: ClosedRange<CGFloat>]
    public var trayBand: ClosedRange<CGFloat>?
    public var extraRowWell: ClosedRange<CGFloat>?
    public var frozenBands: [ClosedRange<CGFloat>]

    public init(
        keyFrames: [UUID: CGRect],
        rowBands: [LayoutEditorModel.RowKind: ClosedRange<CGFloat>],
        trayBand: ClosedRange<CGFloat>?,
        extraRowWell: ClosedRange<CGFloat>?,
        frozenBands: [ClosedRange<CGFloat>] = []
    ) {
        self.keyFrames = keyFrames
        self.rowBands = rowBands
        self.trayBand = trayBand
        self.extraRowWell = extraRowWell
        self.frozenBands = frozenBands
    }
}

/// One unused key in the tray. Derived, never stored.
public struct TrayItem: Identifiable, Equatable, Sendable {
    public var id: SlotAction { action }
    public let action: SlotAction

    /// Literals are stamps. Everything else is unique, like an app on the home screen.
    public var isRepeatable: Bool {
        if case .text = action { return true }
        return false
    }
}

/// Legal VoiceOver (and context) actions for one placed key.
///
/// The list is the rail: an illegal remove is not present.
public enum KeyA11yAction: Equatable, Hashable, Sendable {
    case moveLeft
    case moveRight
    case moveToRow(LayoutEditorModel.RowKind)
    case remove
    case widen
    case narrow
    case fillWidth
    case inspect

    public var title: String {
        switch self {
        case .moveLeft: return "Move left"
        case .moveRight: return "Move right"
        case .moveToRow(let kind): return "Move to \(kind.title.lowercased())"
        case .remove: return "Remove"
        case .widen: return "Increase width"
        case .narrow: return "Decrease width"
        case .fillWidth: return "Fill the row"
        case .inspect: return "Inspect"
        }
    }
}

public enum TrayA11yAction: Equatable, Hashable, Sendable {
    case addTo(LayoutEditorModel.RowKind)

    public var title: String {
        switch self {
        case .addTo(let kind): return "Add to \(kind.title.lowercased())"
        }
    }
}

/// The layout editor's state.
///
/// **No SwiftUI in here on purpose.** It is arithmetic over a
/// `KeyboardCustomization`, and keeping it in the package rather than beside the
/// screen is what lets `LayoutEditorTests` drive every edit the editor can make
/// without standing a view up. The screen observes it and draws.
@MainActor
public final class LayoutEditorModel: ObservableObject {

    /// Which editable row a key belongs to.
    ///
    /// The suggestion bar's two ends are rows as far as the arithmetic is
    /// concerned; only the drawing differs. That is what keeps move, remove and
    /// retarget from being written twice.
    public enum RowKind: String, CaseIterable, Sendable {
        case cursor, bottom, barLeading, barTrailing

        /// **Spoken, not internal.** These reach VoiceOver through
        /// `KeyA11yAction.moveToRow`, `TrayA11yAction.addTo` and the canvas key's
        /// own label, so they have to be the names the screen uses. `.cursor` was
        /// "Extra row" — the name of a switch that no longer exists and never
        /// described what is on the row — while every visible label on the editor
        /// called it the action row, and the bar ends were "Bar, leading" against
        /// a card reading "Left end".
        public var title: String {
            switch self {
            case .bottom: return "Bottom row"
            case .cursor: return "Action row"
            case .barLeading: return "Suggestion bar, left end"
            case .barTrailing: return "Suggestion bar, right end"
            }
        }
    }

    /// Twenty steps. Deep enough that an experiment is recoverable, shallow
    /// enough that the stack is not a second copy of the feature.
    public static let undoLimit = 20

    /// How far past a midpoint the finger must travel before the row re-orders
    /// again, as a fraction of the key's width.
    public static let reorderHysteresis: CGFloat = 0.15

    @Published public var draft: KeyboardCustomization {
        didSet {
            // The moment the draft stops matching the preset exactly, it is a
            // custom layout with a base. `basedOn` survives, so Reset has
            // somewhere to go and the label can say where it came from.
            if let preset = draft.preset,
                LayoutPreset.named(preset)?.customization != draft
            {
                draft.preset = nil
            }
        }
    }

    @Published public var selection: SlotSpec?

    @Published public private(set) var session: DragSession?

    @Published public private(set) var resize: ResizeSession?

    private var history: [KeyboardCustomization] = []
    private var lastDragGeometry: CanvasGeometry?

    public init(layout: KeyboardCustomization) {
        self.draft = layout
    }

    // MARK: Derived

    /// What the canvas draws. A copy of `draft` with the proposed target (or
    /// home) applied. Not stored. Not an undoable assignment.
    public var displayed: KeyboardCustomization {
        if let session { return projected(session) }
        if let resize { return projected(resize) }
        return draft
    }

    /// Catalogue minus unique actions already on the draft. `.text` templates
    /// stay offered. An in-flight tray lift stays in the list so the chip that
    /// owns the gesture is not torn down.
    public var tray: [TrayItem] {
        let placed = Set(
            (draft.bottomRow + draft.cursorRow + draft.barLeading + draft.barTrailing)
                .map(\.action)
                .filter { action in
                    if case .text = action { return false }
                    return true
                }
        )
        return SlotAction.catalogue.compactMap { action in
            let item = TrayItem(action: action)
            if item.isRepeatable || !placed.contains(action) { return item }
            return nil
        }
    }

    // MARK: Reading

    public var issues: [LayoutIssue] {
        LayoutValidator.issues(in: draft)
    }

    public var isUsable: Bool { LayoutValidator.isUsable(draft) }

    public var canUndo: Bool { !history.isEmpty }

    public func row(_ kind: RowKind) -> [SlotSpec] {
        switch kind {
        case .bottom: return draft.bottomRow
        case .cursor: return draft.cursorRow
        case .barLeading: return draft.barLeading
        case .barTrailing: return draft.barTrailing
        }
    }

    /// Which row a key is in, or nil if it is not in the draft at all.
    public func rowKind(of slot: SlotSpec) -> RowKind? {
        RowKind.allCases.first { kind in row(kind).contains { $0.id == slot.id } }
    }

    /// What a row may hold. The bar is a narrower list than the grid.
    public func catalogue(for kind: RowKind) -> [SlotAction] {
        switch kind {
        case .barLeading, .barTrailing: return SuggestionBar.barCatalogue
        case .bottom, .cursor: return SlotAction.catalogue
        }
    }

    public func canRemove(_ slot: SlotSpec) -> LayoutValidator.RemovalVerdict {
        LayoutValidator.canRemove(slot, from: draft)
    }

    public func canAccept(_ action: SlotAction, in kind: RowKind) -> Bool {
        catalogue(for: kind).contains(action)
    }

    // MARK: Drag

    public func beginDrag(_ slot: SlotSpec) {
        guard session == nil, resize == nil, let kind = rowKind(of: slot),
            let index = row(kind).firstIndex(where: { $0.id == slot.id })
        else { return }
        lastDragGeometry = nil
        let home: DropTarget = .board(row: kind, index: index)
        session = DragSession(
            origin: .board(slot),
            lifted: slot,
            home: home,
            proposed: home,
            awaitingGeometry: false
        )
    }

    @discardableResult
    public func beginDragFromTray(_ action: SlotAction) -> UUID? {
        guard session == nil, resize == nil, SlotAction.catalogue.contains(action) else {
            return nil
        }
        let lifted = SlotSpec(action: action)
        lastDragGeometry = nil
        session = DragSession(
            origin: .tray(action),
            lifted: lifted,
            home: .tray,
            proposed: nil,
            awaitingGeometry: false
        )
        return lifted.id
    }

    public func updateDrag(at point: CGPoint, in geometry: CanvasGeometry) {
        guard var current = session else { return }
        if current.awaitingGeometry {
            guard geometry != lastDragGeometry else { return }
            current.awaitingGeometry = false
        }
        let raw = Self.dropTarget(at: point, in: geometry, dragging: current.lifted.id)
        let proposed: DropTarget?
        if let raw {
            guard isLegal(raw, for: current) else { return }
            proposed = refined(raw, at: point, in: geometry, session: current)
        } else {
            proposed = nil
        }
        guard proposed != current.proposed else {
            if current != session { session = current }
            return
        }
        let before = projected(current)
        current.proposed = proposed
        if projected(current) != before {
            current.awaitingGeometry = true
            lastDragGeometry = geometry
        }
        session = current
    }

    /// No-op unless `id` is the key in this session. A late `onEnded` from
    /// another key must not commit this drag.
    public func endDrag(for id: UUID) {
        guard let session, session.lifted.id == id else { return }
        let target = session.proposed ?? session.home
        let lifted = session.lifted
        self.session = nil
        lastDragGeometry = nil
        if case .tray = target, !canRemove(lifted).isAllowed, case .board = session.origin {
            return
        }
        edit { Self.apply(target, lifted: lifted, to: &$0) }
    }

    public func cancelDrag() {
        session = nil
        lastDragGeometry = nil
    }

    /// Space is the leftover. Resizing it would steal the row's only flexible key.
    public func canResize(_ slot: SlotSpec) -> Bool {
        slot.action != .space && rowKind(of: slot) != nil
    }

    public func beginResize(_ slot: SlotSpec) {
        guard session == nil, resize == nil, canResize(slot) else { return }
        resize = ResizeSession(slotID: slot.id, start: slot.width, proposed: slot.width)
    }

    public func updateResize(_ width: SlotWidth) {
        guard var current = resize else { return }
        guard width != current.proposed else { return }
        current.proposed = width
        resize = current
        if var selected = selection, selected.id == current.slotID {
            selected.width = width
            selection = selected
        }
    }

    public func endResize(for id: UUID) {
        guard let resize, resize.slotID == id else { return }
        let proposed = resize.proposed
        let start = resize.start
        self.resize = nil
        guard proposed != start else { return }
        edit { layout in
            for kind in RowKind.allCases {
                Self.write(kind, in: &layout) { keys in
                    guard let index = keys.firstIndex(where: { $0.id == id }) else { return }
                    keys[index].width = proposed
                }
            }
        }
    }

    public func cancelResize() {
        resize = nil
        if let selection {
            self.selection =
                RowKind.allCases.lazy
                .compactMap { kind in self.row(kind).first { $0.id == selection.id } }
                .first
        }
    }

    // MARK: Reading the drawn keyboard
    //
    // **These two live here rather than beside the canvas, and the comment that
    // sent them here named a test file that did not exist.** They were `static`
    // on `LayoutView` "so `LayoutFrameMappingTests` can drive it" — and nothing
    // in the repo could, because the app target has no unit-test bundle at all
    // and `AIKeyboardCoreTests` cannot see it. They are pure arithmetic over
    // what the keyboard drew, which is the same reason everything else in this
    // file is here: `LayoutEditorTests` drives the whole editor without standing
    // a view up.

    /// Matches the keyboard's compiled key ids back to the model's slots.
    ///
    /// A compiled key is `char-,#a1b2c3d4`: the suffix is the first eight
    /// characters of the slot's `UUID`, which is what makes two commas on one
    /// row two identities rather than one `ForEach` identity.
    public static func mapFrames(
        _ frames: [String: CGRect], to slots: [SlotSpec]
    ) -> [UUID: CGRect] {
        var mapped: [UUID: CGRect] = [:]
        for slot in slots {
            let suffix = "#\(slot.id.uuidString.prefix(8))"
            if let match = frames.first(where: { $0.key.hasSuffix(suffix) }) {
                mapped[slot.id] = match.value
            }
        }
        return mapped
    }

    /// The bands the user may not drop into, merged into one range per drawn row.
    ///
    /// Compiled letter, digit, shift and delete keys have no `#uuid` suffix —
    /// those rows come from `letterLayouts` and are not the user's to rearrange.
    /// Overlapping rects merge, so a grouped double-height band is one range.
    public static func frozenBands(from frames: [String: CGRect]) -> [ClosedRange<CGFloat>] {
        var rows: [ClosedRange<CGFloat>] = []
        for (id, rect) in frames where !id.contains("#") {
            let band = rect.minY...rect.maxY
            if let index = rows.firstIndex(where: {
                $0.lowerBound <= band.upperBound && band.lowerBound <= $0.upperBound
            }) {
                let merged = rows[index]
                rows[index] =
                    min(
                        merged.lowerBound, band.lowerBound)...max(
                        merged.upperBound, band.upperBound)
            } else {
                rows.append(band)
            }
        }
        return rows
    }

    /// Pure hit test. `updateDrag` is the only production caller.
    ///
    /// Priority: trayBand, extraRowWell (overlaps the top frozen row on
    /// purpose), frozen letter/digit rows (refuse), then rowBands in screen
    /// order (cursor, bottom).
    public static func dropTarget(
        at point: CGPoint,
        in geometry: CanvasGeometry,
        dragging dragged: UUID?
    ) -> DropTarget? {
        if let tray = geometry.trayBand, tray.contains(point.y) {
            return .tray
        }
        if let well = geometry.extraRowWell, well.contains(point.y) {
            return .board(row: .cursor, index: 0)
        }
        if geometry.frozenBands.contains(where: { $0.contains(point.y) }) {
            return nil
        }
        for kind in [RowKind.cursor, RowKind.bottom] {
            guard let band = geometry.rowBands[kind], band.contains(point.y) else {
                continue
            }
            let frames = rowFrames(kind, in: geometry, excluding: dragged)
            return .board(row: kind, index: insertionIndex(at: point.x, in: frames))
        }
        return nil
    }

    /// Midpoint rule, unchanged. Index is into the frames passed in, which
    /// must already exclude the dragged key.
    public static func insertionIndex(at x: CGFloat, in frames: [CGRect]) -> Int {
        frames.reduce(0) { index, frame in x > frame.midX ? index + 1 : index }
    }

    /// Midpoint rule with a dead band so a finger on a boundary does not swap
    /// two keys every frame.
    public static func insertionIndex(
        at x: CGFloat, in frames: [CGRect],
        hysteresis: CGFloat, current: Int
    ) -> Int {
        let raw = insertionIndex(at: x, in: frames)
        guard raw != current, !frames.isEmpty else { return raw }
        if raw > current {
            guard current < frames.count else { return raw }
            let frame = frames[current]
            return x > frame.midX + hysteresis * frame.width ? raw : current
        }
        let frame = frames[min(max(current, 1), frames.count) - 1]
        return x < frame.midX - hysteresis * frame.width ? raw : current
    }

    // MARK: VoiceOver

    public func accessibilityActions(for slot: SlotSpec) -> [KeyA11yAction] {
        guard let kind = rowKind(of: slot),
            let index = row(kind).firstIndex(where: { $0.id == slot.id })
        else { return [] }
        let keys = row(kind)
        var result: [KeyA11yAction] = []
        if index > 0 { result.append(.moveLeft) }
        if index < keys.count - 1 { result.append(.moveRight) }
        for other in [RowKind.cursor, RowKind.bottom]
        where other != kind && canAccept(slot.action, in: other) {
            result.append(.moveToRow(other))
        }
        switch slot.width {
        case .fill:
            result.append(.narrow)
        case .units(let value):
            if value > SlotWidth.minimumUnits { result.append(.narrow) }
            if value < SlotWidth.maximumUnits { result.append(.widen) }
            result.append(.fillWidth)
        }
        if canRemove(slot).isAllowed { result.append(.remove) }
        result.append(.inspect)
        return result
    }

    public func trayActions(for action: SlotAction) -> [TrayA11yAction] {
        RowKind.allCases.compactMap { kind in
            guard canAccept(action, in: kind) else { return nil }
            return .addTo(kind)
        }
    }

    public func perform(_ action: KeyA11yAction, on slot: SlotSpec) {
        cancelDrag()
        switch action {
        case .moveLeft: move(slot, by: -1)
        case .moveRight: move(slot, by: 1)
        case .moveToRow(let kind): move(slot, to: kind, at: row(kind).count)
        case .remove: remove(slot)
        case .widen:
            if case .units(let value) = slot.width {
                setWidth(.clampedUnits(value + 0.5), for: slot)
            }
        case .narrow:
            switch slot.width {
            case .fill: setWidth(.units(1), for: slot)
            case .units(let value): setWidth(.clampedUnits(value - 0.5), for: slot)
            }
        case .fillWidth: setWidth(.fill, for: slot)
        case .inspect: selection = slot
        }
    }

    public func perform(_ action: TrayA11yAction, adding catalogueAction: SlotAction) {
        cancelDrag()
        switch action {
        case .addTo(let kind): add(catalogueAction, to: kind)
        }
    }

    // MARK: Editing

    public func apply(preset: LayoutPreset) {
        edit { $0 = preset.customization }
        selection = nil
    }

    public func reset() {
        guard let base = LayoutPreset.named(draft.basedOn) else { return }
        edit { $0 = base.customization }
        selection = nil
    }

    public func add(_ action: SlotAction, to kind: RowKind) {
        edit { layout in
            Self.write(kind, in: &layout) { $0.append(SlotSpec(action: action)) }
        }
    }

    public func remove(_ slot: SlotSpec) {
        guard canRemove(slot).isAllowed, let kind = rowKind(of: slot) else { return }
        edit { layout in
            Self.write(kind, in: &layout) { $0.removeAll { $0.id == slot.id } }
        }
        if selection?.id == slot.id { selection = nil }
    }

    /// Moves a key `offset` places within its own row.
    ///
    /// Out of range is a no-op rather than a clamp: Move left on the leftmost key
    /// should do nothing, not silently re-anchor it somewhere the user did not
    /// point at.
    public func move(_ slot: SlotSpec, by offset: Int) {
        guard let kind = rowKind(of: slot) else { return }
        let current = row(kind)
        guard let index = current.firstIndex(where: { $0.id == slot.id }) else { return }
        let destination = index + offset
        guard current.indices.contains(destination) else { return }
        edit { layout in
            Self.write(kind, in: &layout) { keys in
                let moved = keys.remove(at: index)
                keys.insert(moved, at: destination)
            }
        }
    }

    /// Moves a key to an absolute index, possibly in another row.
    ///
    /// **`index` is an index into the row *without* this key in it**, because the
    /// key is removed before it is inserted.
    public func move(_ slot: SlotSpec, to kind: RowKind, at index: Int) {
        guard let origin = rowKind(of: slot) else { return }
        edit { layout in
            Self.write(origin, in: &layout) { $0.removeAll { $0.id == slot.id } }
            Self.write(kind, in: &layout) { keys in
                keys.insert(slot, at: min(max(0, index), keys.count))
            }
        }
    }

    public func setWidth(_ width: SlotWidth, for slot: SlotSpec) {
        let clamped: SlotWidth
        switch width {
        case .fill: clamped = .fill
        case .units(let value): clamped = SlotWidth.clampedUnits(value)
        }
        mutate(slot) { $0.width = clamped }
    }

    public func setAction(_ action: SlotAction, for slot: SlotSpec) {
        mutate(slot) { $0.action = action }
    }

    public func setNumberRow(enabled: Bool) {
        edit { $0.showsNumberRow = enabled }
    }

    // **There is deliberately no `setExtraRow(enabled:)`, and there was one.**
    // It backed an "Extra row" switch in the editor, and that row is the
    // *action* row — CopyClip, Fix, settings, Rewrite, dictation — so one tap on
    // a control named after a position rather than its contents emptied the
    // product's whole AI surface. The row empties a key at a time by dragging,
    // and any preset fills it again.

    /// **Takes the band it is changing, and the letters are one band.** The
    /// action row and the space row each answer to their own slider; the three
    /// letter rows and the number row share one, because a stagger inside the
    /// letter grid reads as a rendering fault rather than a preference. See
    /// `LayoutGeometry.RowBand`.
    public func setKeyHeight(_ height: CGFloat, for band: LayoutGeometry.RowBand = .letters) {
        edit {
            $0.geometry.setHeight(
                Self.clamp(height, to: LayoutGeometry.keyHeightRange), for: band)
        }
    }

    public func setRowSpacing(_ spacing: CGFloat) {
        edit { $0.geometry.rowSpacing = Self.clamp(spacing, to: LayoutGeometry.rowSpacingRange) }
    }

    public func setReach(_ reach: Reach) {
        edit { $0.geometry.reach = reach }
    }

    // MARK: Undo

    public func undo() {
        guard let previous = history.popLast() else { return }
        draft = previous
        // The selection holds a value, not a reference, so it names a key that
        // may no longer exist or may have different contents. Re-resolve it by id
        // and drop it if the undone step removed it.
        selection = selection.flatMap { current in
            RowKind.allCases.lazy
                .compactMap { kind in self.row(kind).first { $0.id == current.id } }
                .first
        }
    }

    // MARK: Plumbing

    /// Every committed mutation. Session updates do not enter here.
    /// A live drag is abandoned first so a preset tap cannot keep a lifted key
    /// from the previous layout.
    private func edit(_ change: (inout KeyboardCustomization) -> Void) {
        if session != nil {
            session = nil
            lastDragGeometry = nil
        }
        if resize != nil { cancelResize() }
        let before = draft
        var next = draft
        change(&next)
        guard next != before else { return }
        history.append(before)
        if history.count > Self.undoLimit { history.removeFirst() }
        draft = next
    }

    private func projected(_ session: DragSession) -> KeyboardCustomization {
        var layout = draft
        Self.apply(session.proposed ?? session.home, lifted: session.lifted, to: &layout)
        return layout
    }

    private func projected(_ resize: ResizeSession) -> KeyboardCustomization {
        var layout = draft
        for kind in RowKind.allCases {
            Self.write(kind, in: &layout) { keys in
                guard let index = keys.firstIndex(where: { $0.id == resize.slotID }) else {
                    return
                }
                keys[index].width = resize.proposed
            }
        }
        return layout
    }

    /// The one placement. `displayed` and `endDrag` both call this, so a preview
    /// cannot disagree with the commit.
    private static func apply(
        _ target: DropTarget, lifted: SlotSpec, to layout: inout KeyboardCustomization
    ) {
        layout.bottomRow.removeAll { $0.id == lifted.id }
        layout.cursorRow.removeAll { $0.id == lifted.id }
        layout.barLeading.removeAll { $0.id == lifted.id }
        layout.barTrailing.removeAll { $0.id == lifted.id }
        switch target {
        case .board(let row, let index):
            write(row, in: &layout) { keys in
                keys.insert(lifted, at: min(max(0, index), keys.count))
            }
        case .tray:
            break
        }
    }

    private func mutate(_ slot: SlotSpec, _ change: (inout SlotSpec) -> Void) {
        guard let kind = rowKind(of: slot) else { return }
        edit { layout in
            Self.write(kind, in: &layout) { keys in
                guard let index = keys.firstIndex(where: { $0.id == slot.id }) else { return }
                change(&keys[index])
            }
        }
        // The selection is a copy, so it goes stale the moment the key it names is
        // edited — and the inspector reads its width and action off that copy.
        if selection?.id == slot.id {
            selection = row(kind).first { $0.id == slot.id }
        }
    }

    private static func write(
        _ kind: RowKind, in layout: inout KeyboardCustomization,
        _ change: (inout [SlotSpec]) -> Void
    ) {
        switch kind {
        case .bottom: change(&layout.bottomRow)
        case .cursor: change(&layout.cursorRow)
        case .barLeading: change(&layout.barLeading)
        case .barTrailing: change(&layout.barTrailing)
        }
    }

    private static func clamp(_ value: CGFloat, to range: ClosedRange<CGFloat>) -> CGFloat {
        min(range.upperBound, max(range.lowerBound, value))
    }

    private func isLegal(_ target: DropTarget, for session: DragSession) -> Bool {
        switch target {
        case .tray:
            if case .tray = session.origin { return true }
            return canRemove(session.lifted).isAllowed
        case .board(let row, _):
            if canAccept(session.lifted.action, in: row) { return true }
            if case .board = session.origin {
                return rowKind(of: session.lifted) == row
            }
            return false
        }
    }

    private func refined(
        _ target: DropTarget, at point: CGPoint, in geometry: CanvasGeometry,
        session: DragSession
    ) -> DropTarget {
        guard case .board(let row, _) = target,
            case .board(let currentRow, let currentIndex) = session.proposed,
            row == currentRow
        else { return target }
        let frames = Self.rowFrames(row, in: geometry, excluding: session.lifted.id)
        let index = Self.insertionIndex(
            at: point.x, in: frames,
            hysteresis: Self.reorderHysteresis, current: currentIndex)
        return .board(row: row, index: index)
    }

    private static func rowFrames(
        _ kind: RowKind, in geometry: CanvasGeometry, excluding dragged: UUID?
    ) -> [CGRect] {
        guard let band = geometry.rowBands[kind] else { return [] }
        return geometry.keyFrames
            .filter { id, rect in
                dragged.map { $0 != id } ?? true && band.contains(rect.midY)
            }
            .map(\.value)
            .sorted { $0.minX < $1.minX }
    }
}
