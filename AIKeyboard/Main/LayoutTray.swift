import SwiftUI
import AIKeyboardCore

// MARK: - Overlay helpers

struct LayoutChromeFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

struct LayoutTrayFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

/// Backs `availableHeight`. See `hasRoomForWorkbenchFloor`.
struct LayoutViewportHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Backs `shelfHeight`. See `hasRoomForWorkbenchFloor`.
struct ShelfHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct LayoutTray: View {
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

