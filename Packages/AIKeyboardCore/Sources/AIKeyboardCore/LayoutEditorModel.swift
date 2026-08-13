import Combine
import Foundation

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

        public var title: String {
            switch self {
            case .bottom: return "Bottom row"
            case .cursor: return "Extra row"
            case .barLeading: return "Bar, leading"
            case .barTrailing: return "Bar, trailing"
            }
        }
    }

    /// Twenty steps. Deep enough that an experiment is recoverable, shallow
    /// enough that the stack is not a second copy of the feature.
    public static let undoLimit = 20

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

    private var history: [KeyboardCustomization] = []

    public init(layout: KeyboardCustomization) {
        self.draft = layout
    }

    // MARK: Reading

    public var issues: [LayoutIssue] {
        LayoutValidator.issues(in: draft)
    }

    public var isUsable: Bool { LayoutValidator.isUsable(draft) }

    public var canUndo: Bool { !history.isEmpty }

    /// The rows the editor lists, in the order they appear on the keyboard. The
    /// extra row is first because `KeyboardView` draws it above the letters; it is
    /// absent when it is switched off, which is what an empty `cursorRow` means.
    public var visibleRows: [RowKind] {
        RowKind.allCases.filter { $0 != .cursor || !draft.cursorRow.isEmpty }
    }

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

    /// Moves a key to an absolute index, possibly in another row. The drag
    /// gesture's only mutation.
    ///
    /// **`index` is an index into the row *without* this key in it**, because the
    /// key is removed before it is inserted. A caller computing it from rendered
    /// frames must therefore leave the dragged key's own frame out — `LayoutView`
    /// does, with a `filter` — or every rightward drag inside one row lands one
    /// slot too far along. Stated here because the arithmetic is in
    /// `insertionIndex(at:in:)`, the filtering is in the view, and nothing but
    /// this sentence connects the two.
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

    /// **Seeded, not empty.** A row switched on and left blank is a row the user
    /// has to populate before it does anything.
    ///
    /// Seeded with `KeyboardCustomization.actionRow` rather than with cursor keys:
    /// that is what the row ships holding, so switching it off and on again gives
    /// back what was there rather than something else. It used to seed
    /// arrows-and-hide, which was right while the row was called the cursor row
    /// and wrong the moment it became the action row.
    public func setExtraRow(enabled: Bool) {
        edit { layout in
            layout.cursorRow = enabled ? KeyboardCustomization.actionRow : []
        }
        if enabled == false, let selection, rowKind(of: selection) == nil {
            self.selection = nil
        }
    }

    public func setKeyHeight(_ height: CGFloat) {
        edit { $0.geometry.keyHeight = Self.clamp(height, to: LayoutGeometry.keyHeightRange) }
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

    /// Every mutation goes through here, so nothing can change the draft without
    /// leaving a step on the undo stack.
    private func edit(_ change: (inout KeyboardCustomization) -> Void) {
        let before = draft
        var next = draft
        change(&next)
        guard next != before else { return }
        history.append(before)
        if history.count > Self.undoLimit { history.removeFirst() }
        draft = next
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

    // MARK: Drag arithmetic

    /// Where a drop at this x lands, given the row's key frames in the same
    /// coordinate space.
    ///
    /// The midpoint of each key is the boundary, so a finger past the middle of a
    /// key means "after it". Static and taking frames rather than reading a view,
    /// because a gesture cannot be tested and this can.
    public static func insertionIndex(at x: CGFloat, in frames: [CGRect]) -> Int {
        frames.reduce(0) { index, frame in x > frame.midX ? index + 1 : index }
    }
}
