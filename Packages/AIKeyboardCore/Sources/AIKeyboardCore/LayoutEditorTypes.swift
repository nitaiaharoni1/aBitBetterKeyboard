import CoreGraphics
import Foundation

extension LayoutEditorModel {
    /// Which editable row a key belongs to. The suggestion bar ends are rows to
    /// the editor arithmetic, so move, remove, and retarget stay shared.
    public enum RowKind: String, CaseIterable, Sendable {
        case cursor, bottom, barLeading, barTrailing

        /// Spoken labels reach VoiceOver through the canvas and editor actions.
        public var title: String {
            switch self {
            case .bottom: return "Bottom row"
            case .cursor: return "Action row"
            case .barLeading: return "Suggestion bar, left end"
            case .barTrailing: return "Suggestion bar, right end"
            }
        }
    }

    public func trayActions(for action: SlotAction) -> [TrayA11yAction] {
        RowKind.allCases.compactMap { kind in
            guard canAccept(action, in: kind) else { return nil }
            return .addTo(kind)
        }
    }

    public func perform(_ action: TrayA11yAction, adding catalogueAction: SlotAction) {
        cancelDrag()
        switch action {
        case .addTo(let kind): add(catalogueAction, to: kind)
        }
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
}

/// Where a lift started. Tray origins mint a `SlotSpec` for the session only.
public enum DragOrigin: Equatable, Sendable { case board(SlotSpec); case tray(SlotAction) }

/// Where the finger currently proposes to drop. `.board` indexes the row without the lifted key.
public enum DropTarget: Equatable, Sendable { case board(row: LayoutEditorModel.RowKind, index: Int); case tray }

public struct DragSession: Equatable, Sendable {
    public let origin: DragOrigin
    public let lifted: SlotSpec
    /// Captured at lift so a torn-down board drag cannot fall into the tray.
    public let home: DropTarget
    public var proposed: DropTarget?
    /// Re-ordering moves the frames that decide the next re-order.
    public var awaitingGeometry: Bool
}

/// An in-flight handle drag. `draft` stays put until `endResize`.
public struct ResizeSession: Equatable, Sendable {
    public let slotID: UUID
    public let start: SlotWidth
    public var proposed: SlotWidth
}

/// What the view measured, in the keyboard's own bounds.
public struct CanvasGeometry: Equatable, Sendable {
    public var keyFrames: [UUID: CGRect]
    public var rowBands: [LayoutEditorModel.RowKind: ClosedRange<CGFloat>]
    public var trayBand: ClosedRange<CGFloat>?
    public var extraRowWell: ClosedRange<CGFloat>?
    public var frozenBands: [ClosedRange<CGFloat>]

    public init(keyFrames: [UUID: CGRect], rowBands: [LayoutEditorModel.RowKind: ClosedRange<CGFloat>], trayBand: ClosedRange<CGFloat>?, extraRowWell: ClosedRange<CGFloat>?, frozenBands: [ClosedRange<CGFloat>] = []) {
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
    public var isRepeatable: Bool { if case .text = action { return true }; return false }
}

/// Legal VoiceOver (and context) actions for one placed key.
public enum KeyA11yAction: Equatable, Hashable, Sendable {
    case moveLeft, moveRight, moveToRow(LayoutEditorModel.RowKind), remove, widen, narrow, fillWidth, inspect
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
    public var title: String { switch self { case .addTo(let kind): return "Add to \(kind.title.lowercased())" } }
}
