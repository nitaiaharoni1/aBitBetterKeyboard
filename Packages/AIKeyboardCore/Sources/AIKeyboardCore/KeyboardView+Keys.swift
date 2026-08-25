import SwiftUI

extension KeyboardView {

    // MARK: What a panel may cover

    /// Whether the emoji grid and the CopyClip list are allowed to stand over
    /// this row.
    ///
    /// **The bottom row is the one that says no, and the reason is that the key
    /// closing the panel is in it.** Emoji ships beside `123` and `KeyView.label`
    /// turns it into `ABC` / `אבג` while the grid is up, which is the iOS
    /// arrangement; a panel drawn over that row takes the only exit off the
    /// screen. This was true the moment Emoji and the gear traded seats, and
    /// nothing else in the build could see it — `Overlay.showsLetterKeys` hides
    /// rows without knowing what is in them, and `LayoutValidator` has no opinion
    /// about a key that is present but covered.
    ///
    /// It is also the same split the language swipe already needed: the rows a
    /// panel replaces are exactly the rows that slide, and the space row stays put
    /// under both because the thumb is on it. One rule, two callers, rather than
    /// two filters that happen to agree.
    ///
    /// `EmojiModeTests.testAnOpenEmojiGridAlwaysHasAWayBack` is what holds it.
    static func panelCovers(rowID: Int) -> Bool {
        rowID != KeyboardLayout.RowID.bottom
    }

    /// Whether the bottom row is dropped outright rather than merely uncovered.
    ///
    /// **The CopyClip list is the one panel with nothing of its own under that
    /// row, so it is the one panel the row can be taken away for.** The rule
    /// above keeps `123`, space, the full stop, return and Emoji on screen
    /// because a panel that covered them would take its own exit with it — and
    /// for the emoji grid that is the whole argument, since `אבג` *is* that
    /// Emoji key (`KeyView.label`'s `isEmojiOpen` branch). CopyClip is not
    /// reached from the bottom row and is not left from it: the key that closes
    /// the list is in the action row, which `Overlay.showsActionRow` keeps drawn,
    /// and the two controls the list actually wants — undo and delete — are
    /// `CopyClipControlRow` inside the panel. So five keys sat under it doing
    /// nothing but cost the clips a row and a half of height.
    ///
    /// **Asked of the exit rather than hardcoded**, because the layout editor
    /// lets a user move CopyClip anywhere, and a user who put it in the bottom
    /// row would be dropping the only way out along with the row. That is the
    /// defect `KeyboardCustomization.actionRow`'s own note records happening to
    /// Emoji, arriving through a different door. Landscape is answered by the
    /// same line for free: `Theme.Metrics.landscapeLayout(basedOn:)` empties
    /// `cursorRow`, so this returns false there and the row stays — which is
    /// what landscape wants anyway, having shed the action row and having about
    /// 60 pt of panel to spend.
    ///
    /// `.copyclipSearch` is deliberately not included: search puts the letters
    /// back and needs a space bar and a return key under them.
    static func dropsBottomRow(
        overlay: KeyboardOverlay, layout: KeyboardCustomization
    ) -> Bool {
        guard overlay == .copyclip else { return false }
        return layout.cursorRow.contains { $0.action == .copyclip }
    }

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
            // slides with the language, matching the strip rather than a pager —
            // and everything above it is also exactly what a panel replaces, which
            // is one rule rather than two coincidences. See `panelCovers(rowID:)`.
            let slidingRows = letterRows.filter { Self.panelCovers(rowID: $0.id) }
            let bottomRows = letterRows.filter { !Self.panelCovers(rowID: $0.id) }
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
                    // Letter / number / extra rows slide, and a panel covers
                    // exactly these. Hidden (not removed) while one is up so the
                    // grid keeps the same height.
                    //
                    // **The sliding stack is a ZStack so old and new letters can
                    // overlap for the swipe, and it must not be allowed to grow.**
                    // A ZStack in a GeometryReader eats leftover height. That
                    // leftover sat *between* the backspace row and the space row,
                    // shoved the space row into the bottom edge, and `.clipped()`
                    // then sliced the backspace row's own shadow off. Hugging the
                    // keys restores the same 12pt gap every other row has.
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
                        .opacity(showLetterKeys ? 1 : 0)
                        .allowsHitTesting(showLetterKeys)
                        .keyboardGridChrome(width: gridWidth, reach: layout.geometry.reach)
                    }

                    // Over the letter area only — not over the action row above.
                    // Same width and reach pin as the keys, so one-handed mode
                    // does not leave a full-bleed emoji panel over a narrowed row.
                    if controller.overlay == .emoji {
                        // Still `.bottom` rather than `.letters`, and now for a
                        // different reason. The strip used to *stand in* for the
                        // space row because the panel covered it; the space row is
                        // drawn now, right underneath, so the two are neighbours
                        // and the strip takes its neighbour's height so the eye
                        // reads one band of chrome rather than two of different
                        // sizes.
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
                        // band: its control row is this panel's own neighbour to
                        // the space row and matches its height.
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

                // **Outside the panel's ZStack, so nothing can ever cover it.**
                // It used to be inside, sharing the letters' `showLetterKeys`
                // opacity, and both panels were sized to the whole block — which
                // meant an open emoji grid hid `123`, space, the full stop, return
                // *and* the Emoji key that closes it. While Emoji sat in the
                // action row that cost nothing, because the action row stays
                // drawn; the moment Emoji moved down here it was the only way out
                // of the grid and it was underneath the grid. Drawing this row
                // unconditionally is what makes `KeyView.label`'s `isEmojiOpen`
                // branch reachable: the Emoji key reads `ABC` / `אבג` while the
                // grid is up, which is the iOS arrangement and needs no second key
                // anywhere. `EmojiModeTests.testAnOpenEmojiGridAlwaysHasAWayBack`
                // holds it.
                //
                // The keyboard's published height is untouched — the same three
                // bands in the same order, with the split moved one container up —
                // but the panel is a row shorter, which
                // `EmojiPanel.rowCount(forGridHeight:)` pays for: four rows of
                // emoji in portrait rather than five, and two in landscape rather
                // than five specks.
                //
                // **The CopyClip list is the exception, and `dropsBottomRow` is
                // the whole of it.** Removing the row rather than hiding it is
                // what hands its height to the panel: the letters beside it are
                // `.fixedSize`, so the flexible child of this stack is the panel,
                // and its `CopyClipControlRow` — undo and delete — lands where
                // the space row was. The keyboard's published height does not
                // move, because `Theme.Metrics.keyAreaHeight(for:)` is a
                // function of the layout and knows nothing about overlays.
                if !bottomRows.isEmpty,
                    !Self.dropsBottomRow(overlay: controller.overlay, layout: layout)
                {
                    rowsView(
                        bottomRows, availableWidth: available, unit: unit,
                        height: layout.geometry.height(.bottom),
                        rowSpacing: layout.geometry.rowSpacing
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    .keyboardGridChrome(width: gridWidth, reach: layout.geometry.reach)
                    // **The same layer as the letters, and declared after them.**
                    // These two used to be one container at this z, with the space
                    // row drawn second inside it; splitting them left this one at
                    // the default zero, which is *under* both the letters (2) and
                    // the action row (1). The full stop's long-press strip grows
                    // upward into the letter rows, so it would have been painted
                    // behind them — the same defect `KeyPopupLayer`'s own note
                    // records for the action row. A tie is broken by declaration
                    // order, so this reproduces the old paint order exactly, and it
                    // is also a second reason a panel can never cover this row.
                    .zIndex(KeyPopupLayer.letters)
                }
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
                // stay `.idle` so another key's call can never be the reason
                // they rebuild.
                activity: {
                    let cap = key.cap
                    if cap == .dictation || KeyActivity.hostsWorkingOrbit(cap) {
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
                onCharacterTouch: characterTouchHandler(for: key),
                onPopupLayerChange: popupLayerHandler(for: key)
            )
            // The key redraws when something it draws from moved, and not
            // because the controller published. See `KeyView.==`.
            .equatable()
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
            // **Only the layout editor reads these frames, and the system
            // keyboard was publishing them anyway.** `LayoutView` is the one
            // `onPreferenceChange(KeyFramesKey.self)` in the project — it puts a
            // selection ring and a drop target over the real keyboard rather than
            // over a drawing of one — and `isEditingLayout: true` is passed from
            // exactly that call site. Everywhere else this was a `GeometryReader`
            // and a dictionary merge per key, on every layout pass, feeding a
            // preference with no reader on the other end. `KeyFramesKey`'s own
            // doc comment has named the cost since it was written.
            .background {
                if isEditingLayout {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: KeyFramesKey.self,
                            value: [key.id: proxy.frame(in: .named(Self.frameSpace))])
                    }
                }
            }
        }
    }

    /// Character keys report a touch instead of a press, and its presence is what
    /// makes them wait for the lift (NIT-108, `KeyView.defersCharacterToLift`).
    ///
    /// Every other key stays on `onPress`, which stays immediate. So does this
    /// key's own `onPress`: a VoiceOver rotor pick of an accent has no lift behind
    /// it, so `KeyView.commitAlternate` replays the press rather than opening a
    /// touch nothing would ever close.
    func characterTouchHandler(for key: KeySpec) -> ((CharacterTouchPhase) -> Void)? {
        guard case .character = key.cap else { return nil }
        return { controller.characterTouch($0) }
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
    /// A letter has already inserted its character on the lift one line above the
    /// pick, so picking an accent is a replacement and
    /// `KeyboardController.insertAlternate` is what that means. A grouped key
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
        return { alternate in controller.insertAlternate(alternate) }
    }
}
