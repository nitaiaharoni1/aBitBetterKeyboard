import SwiftUI

extension KeyboardView {

    // MARK: Keys

    var keyGrid: some View {
        GeometryReader { geo in
            // **Landscape sheds the number row and the action row, regardless of
            // what the user turned on.** 402pt of landscape screen height under
            // the same fingerprint-fraction cap portrait uses leaves ≈169pt for
            // the whole keyboard, against 368pt in portrait — not room for two
            // more rows at a usable size. `Theme.Metrics.landscapeLayout(basedOn:)`
            // is also what `keyAreaHeight(for:orientation:)` reads, so the height
            // published to the host and the rows actually drawn here cannot
            // drift apart. See NIT-18.
            let layout: KeyboardCustomization =
                orientation == .landscape
                ? Theme.Metrics.landscapeLayout(basedOn: controller.customization)
                : controller.customization
            // The one place that knows what the user chose. `KeyboardLayout` is a
            // pure function of its arguments and must stay one — reading the dial
            // inside it made every layout test depend on whatever the App Group
            // happened to hold.
            let grouping = controller.groupingLevel
            let columns = KeyboardLayout.columns(
                for: controller.language, plane: controller.plane, grouping: grouping)
            // One-handed narrows the grid and pins it to a side. The keys inside
            // are solved against the narrowed width, so nothing has to know: the
            // whole keyboard is simply drawn in a smaller box.
            let gridWidth = geo.size.width * layout.geometry.reach.widthFraction
            let unit = KeyboardLayout.unitWidth(
                totalWidth: gridWidth,
                spacing: Theme.Metrics.keySpacing,
                sideInset: Theme.Metrics.sideInset,
                columns: columns
            )
            let available = gridWidth - Theme.Metrics.sideInset * 2
            // The editor still draws a globe the user placed from the tray. The
            // device flag stays false so `apply` does not invent one.
            let rows = KeyboardLayout.rows(
                for: controller.language,
                plane: controller.plane,
                showsGlobe: controller.showsGlobeKey || isEditingLayout,
                customization: layout,
                grouping: grouping
            )
            // The action row is `cursorRow`. The compiler appends it last;
            // this view draws it first, above the letter block. Emoji replaces
            // only what sits below it — the letters (and optional number row,
            // and the 123/space row) — so the action keys stay reachable while
            // the grid is open.
            let letterRows = rows.filter { $0.id != KeyboardLayout.RowID.cursor }
            let actionRows = rows.filter { $0.id == KeyboardLayout.RowID.cursor }
            // The space row stays put: the thumb is on it. Everything above it
            // slides with the language, matching the strip rather than a pager.
            let slidingRows = letterRows.filter { $0.id != KeyboardLayout.RowID.bottom }
            let bottomRows = letterRows.filter { $0.id == KeyboardLayout.RowID.bottom }
            // Numbers and symbols draw SwiftKey's extra row. Fit those four into
            // the height three letter rows already occupy, so tapping 123 cannot
            // grow the keyboard past the fingerprint cliff. Letters never take
            // this path: they are the reference. A number row the user turned on
            // raises the reference with `rowCount`, so both planes stay at the
            // shipped key height.
            let referenceSlidingRows = 3 + (layout.showsNumberRow ? 1 : 0)
            let slidingKeyHeight =
                controller.plane == .letters
                ? layout.geometry.height(.letters)
                : Theme.Metrics.fittedKeyHeight(
                    slidingRows: slidingRows.count,
                    referenceRows: referenceSlidingRows,
                    keyHeight: layout.geometry.height(.letters),
                    rowSpacing: layout.geometry.rowSpacing)
            // **Search puts the letters back and takes the action row instead**,
            // which is the exact opposite trade to the panel below it. Typing a
            // search term needs an alphabet, and at 364 pt there is no band left
            // to put one in — so the two halves swap: the panel goes, the keys
            // return, and the matches take the row the actions were in. The
            // actions are not reachable in that state and do not need to be; the
            // key that closes it all is in the suggestion bar's edge, and the
            // search box's own ✕ is a tap away. The results sit between the
            // search box and the letters, which is the only place they fit.
            let searchingEmoji = controller.overlay == .emojiSearch
            let searchingCopyclip = controller.overlay == .copyclipSearch
            let showLetterKeys = controller.overlay.showsLetterKeys
            let showActionRow = controller.overlay.showsActionRow

            VStack(spacing: layout.geometry.rowSpacing) {
                if !actionRows.isEmpty {
                    ZStack {
                        rowsView(
                            actionRows, availableWidth: available, unit: unit,
                            height: layout.geometry.height(.action),
                            rowSpacing: layout.geometry.rowSpacing
                        )
                        .opacity(showActionRow ? 1 : 0)
                        .allowsHitTesting(showActionRow)
                        .keyboardGridChrome(width: gridWidth, reach: layout.geometry.reach)

                        if searchingEmoji {
                            EmojiResultsStrip(
                                controller: controller, height: layout.geometry.height(.action)
                            )
                            .frame(width: gridWidth)
                            .frame(
                                maxWidth: .infinity,
                                alignment: reachAlignment(layout.geometry.reach)
                            )
                            .transition(panelTransition)
                        }
                        if searchingCopyclip {
                            CopyClipResultsStrip(
                                controller: controller, height: layout.geometry.height(.action)
                            )
                            .frame(width: gridWidth)
                            .frame(
                                maxWidth: .infinity,
                                alignment: reachAlignment(layout.geometry.reach)
                            )
                            .transition(panelTransition)
                        }
                    }
                    // Below the letters at rest so a QWERTY callout is not
                    // painted under Reply. Climbs above them only while a
                    // stacked key is held — that raise is what hid the balloon.
                    .zIndex(KeyPopupLayer.actionRow(raised: actionPopupRaised))
                }

                ZStack(alignment: .top) {
                    // Letter / number / extra rows slide; the space row below does
                    // not. Hidden (not removed) while a panel is up so the emoji
                    // grid keeps the same height.
                    //
                    // **The sliding stack is a ZStack so old and new letters can
                    // overlap for the swipe, and it must not be allowed to grow.**
                    // A ZStack in a GeometryReader eats leftover height. That
                    // leftover sat *between* the backspace row and the space row,
                    // shoved the space row into the bottom edge, and `.clipped()`
                    // then sliced the backspace row's own shadow off. Hugging the
                    // keys restores the same 12pt gap every other row has.
                    VStack(spacing: layout.geometry.rowSpacing) {
                        if !slidingRows.isEmpty {
                            ZStack {
                                rowsView(
                                    slidingRows, availableWidth: available, unit: unit,
                                    height: slidingKeyHeight,
                                    rowSpacing: layout.geometry.rowSpacing
                                )
                                .id(controller.language)
                                .transition(
                                    SpaceSwipe.letterTransition(
                                        step: controller.languageSlideStep,
                                        reduceMotion: reduceMotion))
                            }
                            .fixedSize(horizontal: false, vertical: true)
                        }
                        if !bottomRows.isEmpty {
                            rowsView(
                                bottomRows, availableWidth: available, unit: unit,
                                height: layout.geometry.height(.bottom),
                                rowSpacing: layout.geometry.rowSpacing
                            )
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(showLetterKeys ? 1 : 0)
                    .allowsHitTesting(showLetterKeys)
                    .keyboardGridChrome(width: gridWidth, reach: layout.geometry.reach)

                    // Over the letter area only — not over the action row above.
                    // Same width and reach pin as the keys, so one-handed mode
                    // does not leave a full-bleed emoji panel over a narrowed row.
                    if controller.overlay == .emoji {
                        // `.bottom`, not `.letters`: this panel covers the letter
                        // rows *and* the space row, so its category strip is the
                        // row standing where the space bar was.
                        EmojiPanel(
                            controller: controller,
                            keyHeight: layout.geometry.height(.bottom)
                        )
                        .frame(width: gridWidth)
                        .frame(
                            maxWidth: .infinity,
                            alignment: reachAlignment(layout.geometry.reach)
                        )
                        .environment(\.layoutDirection, .leftToRight)
                        .transition(panelTransition)
                    }

                    if controller.overlay == .copyclip {
                        // `.bottom`, for the reason `EmojiPanel` is given the same
                        // band: this panel covers the space row too, so its control
                        // row is the row standing where the space bar was.
                        CopyClipPanel(
                            controller: controller,
                            keyHeight: layout.geometry.height(.bottom)
                        )
                        .frame(width: gridWidth)
                        .frame(
                            maxWidth: .infinity,
                            alignment: reachAlignment(layout.geometry.reach)
                        )
                        .environment(\.layoutDirection, .leftToRight)
                        .transition(panelTransition)
                    }
                }
                .zIndex(KeyPopupLayer.letters)
            }
            .padding(.top, Theme.Metrics.topInset)
            .padding(.bottom, Theme.Metrics.bottomInset)
            .environment(\.keyboardCanvasWidth, geo.size.width)
            .environment(\.keyboardCanvasOriginX, geo.frame(in: .global).minX)
        }
    }

    func rowsView(
        _ rows: [KeyRow], availableWidth: CGFloat, unit: CGFloat, height: CGFloat,
        rowSpacing: CGFloat
    ) -> some View {
        // Must be a VStack: a bare ForEach as a ZStack child stacks each row on
        // the Z axis and they all paint on top of each other.
        VStack(spacing: rowSpacing) {
            ForEach(rows) { row in
                rowView(
                    row, availableWidth: availableWidth, unit: unit,
                    // **A double-height row swallows the spacing it replaced, so
                    // grouping cannot change the keyboard's height.** The band is
                    // two key-heights *plus* the one row gap that used to sit
                    // between the two rows it merged; take that gap away and the
                    // whole keyboard comes up short by it. `heightBias` is the
                    // other height that must net to zero: the numbers row gives
                    // three points to the space row, and those two cancel.
                    height: row.drawnHeight(keyHeight: height, rowSpacing: rowSpacing))
            }
        }
    }

    /// **A row is three parts, and the middle one is the only one that floats.**
    ///
    /// The pinned keys — shift and delete on the letter rows, the plane switch and
    /// delete on the punctuation rows — are drawn hard against the two ends of the
    /// row, and everything between them is centred in what is left. That is what
    /// makes delete the same rect in all sixty-four languages: `KeyboardLayout`
    /// gives it a width in points, and this gives it a position. A single `HStack`
    /// centred the *whole* row instead, so English's six points of slack pushed
    /// delete six points in from the edge while Hebrew's zero points did not, and
    /// the key was still 3pt out of place after being pinned.
    ///
    /// Rows with no pinned keys — the two upper letter rows, the number row, the
    /// bottom row, the action row — fall through this unchanged: the middle block
    /// is the whole row and `maxWidth: .infinity` centres it exactly as before.
    func rowView(
        _ row: KeyRow, availableWidth: CGFloat, unit: CGFloat, height: CGFloat
    ) -> some View {
        let widths = KeyboardLayout.widths(
            for: row,
            totalWidth: availableWidth,
            unitWidth: unit,
            spacing: Theme.Metrics.keySpacing
        )
        let leading = row.keys.first?.width == .pinned ? 1 : 0
        let trailing = row.keys.count > leading && row.keys.last?.width == .pinned ? 1 : 0
        let middle = leading..<(row.keys.count - trailing)

        return HStack(spacing: Theme.Metrics.keySpacing) {
            if leading == 1 { key(at: 0, in: row, widths: widths, unit: unit, height: height) }
            HStack(spacing: Theme.Metrics.keySpacing) {
                ForEach(middle, id: \.self) { index in
                    key(at: index, in: row, widths: widths, unit: unit, height: height)
                }
            }
            .frame(maxWidth: .infinity)
            // Above a trailing pin. `m` sits next to delete; without this
            // the balloon is delete's background. A pin has no callout, so
            // it does not need the same raise.
            .zIndex(1)
            if trailing == 1 {
                key(at: row.keys.count - 1, in: row, widths: widths, unit: unit, height: height)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    func key(
        at index: Int, in row: KeyRow, widths: [CGFloat], unit: CGFloat, height: CGFloat
    ) -> some View {
        if row.keys.indices.contains(index) {
            let key = row.keys[index]
            let hostsReplyPicker =
                key.cap == .aiReply && controller.replyKeyBroadcastPrompt != nil
            let keyWidth = widths.indices.contains(index) ? widths[index] : unit
            KeyView(
                spec: key,
                width: keyWidth,
                height: height,
                language: controller.language,
                shift: controller.shift,
                // Only the space bar carries the language name, and only it
                // reports a touch instead of a press. Both because a slide
                // along it switches language — see `SpaceSwipe`. The list is
                // what it prints codes from and what decides whether it wears
                // the chevrons that say so.
                indication: key.cap == .space ? controller.languageSwitchIndication : nil,
                enabledLanguages: controller.enabledLanguages,
                // Only the one-tap rewrite key, and only because the list comes
                // from a setting the app writes: a `KeySpec` is a value and
                // cannot read the store. Same shape as `enabledLanguages`.
                toneAlternates: key.cap == .quickTone ? controller.toneAlternates : [],
                // Only Fix, and only because the list lives on the controller
                // the way the registers do. Same shape as `toneAlternates`.
                fixAlternates: key.cap == .aiFix ? controller.fixAlternates : [],
                // Only CopyClip, and only because the list lives on the
                // controller the way the registers do. Same shape as the two
                // above.
                copyclipAlternates: key.cap == .copyclip ? controller.copyclipAlternates : [],
                // Only the Emoji key changes what it says when the grid opens,
                // and only it is told. Same shape as `toneAlternates` above.
                isEmojiOpen: key.cap == .emoji && controller.overlay.isEmoji,
                isCopyClipOpen: key.cap == .copyclip && controller.overlay.isCopyClip,
                // The user's own switch when they threw one, and the shipped rule
                // — the row, then a width floor — when they did not. Asked of
                // the key rather than answered here, because the same three-way
                // question is what the editor's tray draws with.
                showsActionCaption: key.showsActionCaption(inRow: row.id, width: keyWidth),
                // Match the action row's labels to every other key. Custom
                // placements keep their action-specific tint.
                usesNeutralActionTint: row.id == KeyboardLayout.RowID.cursor,
                // Which action is currently on screen — filled brand on that
                // key. See `KeyboardController.isActionKeyActive`.
                isActionActive: controller.isActionKeyActive(key.cap),
                // Fix and Rewrite over an empty field. See
                // `KeyboardController.isActionKeyDisabled` for why these two are
                // drawn off rather than left to refuse in the strip.
                isDisabled: controller.isActionKeyDisabled(key.cap),
                // The words behind the dim cap, which is the only form the reason
                // reaches somebody who cannot see it in. There is more than one
                // reason now: an empty field, and a recording in progress.
                disabledHint: controller.actionKeyDisabledReason(key.cap),
                // Only the microphone key, and only it reads this — a recording
                // reports on the key itself now rather than in a strip above the
                // candidates. Same shape as `toneAlternates` and `isEmojiOpen`
                // above: state the `KeySpec` cannot reach on its own.
                dictationState: key.cap == .dictation ? controller.dictationKeyState : .idle,
                // Only the microphone and the three text actions. Letter keys
                // stay `.idle` so a 60 Hz `workingPhase` tick cannot be the
                // reason they rebuild.
                activity: {
                    let cap = key.cap
                    if cap == .dictation || KeyActivity.hostsWorkingSweep(cap) {
                        return KeyActivity.resolve(for: cap, controller: controller)
                    }
                    return .idle
                }(),
                onPress: { controller.press($0, at: $1) },
                // Held backspace deletes words through `deletePreviousWord`, which
                // still clicks and still intercepts emoji search. Forward-delete
                // hold stays one character. Finger-down is still `press`.
                onRepeat: key.cap == .backspace
                    ? { controller.deletePreviousWord() }
                    : key.cap == .deleteForward
                        ? { controller.press(.deleteForward) }
                        : nil,
                onAlternate: alternateHandler(for: key),
                onSpaceTouch: key.cap == .space ? { controller.spaceBarTouch($0) } : nil,
                onPopupLayerChange: popupLayerHandler(for: key)
            )
            // The overlay sits outside KeyView so VoiceOver can see ReplayKit's
            // real button (`.accessibilityElement()` hides descendants). Hits
            // must not also reach the SwiftUI gesture, or one tap both opens
            // the picker and runs `press(.aiReply)`.
            .allowsHitTesting(!hostsReplyPicker)
            .accessibilityHidden(hostsReplyPicker)
            .overlay {
                if hostsReplyPicker {
                    BroadcastPickerButton.overlay(
                        label: KeyCap.aiReply.accessibilityLabel,
                        hint: "Opens the iOS screen broadcast picker.",
                        identifier: "key-\(key.addressableID)",
                        onActivation: { controller.acknowledgeReplyBroadcastTap() }
                    )
                }
            }
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: KeyFramesKey.self,
                        value: [key.id: proxy.frame(in: .named(Self.frameSpace))])
                }
            }
        }
    }

    /// Fix, Rewrite and CopyClip tell the action row to climb over the letters
    /// for the hold. Every other key stays silent so a letter press cannot
    /// raise the row that is supposed to sit under its balloon.
    func popupLayerHandler(for key: KeySpec) -> ((Bool) -> Void)? {
        switch key.cap {
        case .quickTone, .aiFix, .copyclip:
            return { actionPopupRaised = $0 }
        default:
            return nil
        }
    }

    /// What lifting a finger on the second or later item of a key's popup does.
    ///
    /// A letter has already inserted its character on finger-down, so picking an
    /// accent is a replacement: delete, then type the alternate. A grouped key
    /// has already appended a stroke, so picking a letter pins that stroke. The
    /// rewrite key, Fix and CopyClip have deliberately run nothing yet (see
    /// `KeyView.runsOnLift`), so picking a row is the whole action.
    func alternateHandler(for key: KeySpec) -> ((String) -> Void)? {
        if key.cap == .quickTone {
            return controller.toneAlternates.count > 1
                ? { controller.selectTone(named: $0) } : nil
        }
        if key.cap == .aiFix {
            return controller.fixAlternates.count > 1
                ? { controller.selectFix(named: $0) } : nil
        }
        if key.cap == .copyclip {
            return controller.copyclipAlternates.count > 1
                ? { controller.selectCopyclip(named: $0) } : nil
        }
        guard !key.alternates.isEmpty else { return nil }
        // Finger-down already appended a grouped stroke. Delete-then-retype
        // would pin the previous key or end the word.
        if key.groupedLetters != nil {
            return { letter in _ = controller.pinGroupedLetter(letter) }
        }
        return { alternate in
            controller.deleteBackward()
            controller.press(.character(alternate))
        }
    }
}
