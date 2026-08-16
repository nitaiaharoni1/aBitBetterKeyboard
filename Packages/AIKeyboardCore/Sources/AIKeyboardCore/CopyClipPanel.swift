import SwiftUI

/// Clipboard history over the letter keys. The action row stays.
///
/// Cards are letter keys, not a second chrome language: same fill, radius and
/// press as the caps they replaced. The list is vertical because fifty clips
/// are a scroll, not a grid. Search is the same swap emoji already makes:
/// this panel goes, the letters come back, and the action row becomes matches.
///
/// The list does not take the whole panel: `CopyClipControlRow` stands along the
/// bottom, holding the two controls covering the letters took away — a delete
/// key, and a way to take back the clip that was just pasted.
public struct CopyClipPanel: View {
    @ObservedObject var controller: KeyboardController

    /// The keyboard's own key height, so the control row is the same size as the
    /// space row it stands where — passed in for the reason `EmojiPanel` takes
    /// it, because `LayoutGeometry.keyHeight` is a user setting between 36 and 56.
    var keyHeight: CGFloat = Theme.Metrics.keyHeight

    /// A new pasteboard generation is waiting and offering `UIPasteControl`
    /// is the whole reason this file imports the state at all.
    private var awaitsPasteControl: Bool { controller.copyclipCaptureState == .control }

    public var body: some View {
        VStack(spacing: 0) {
            Group {
                if controller.clips.isEmpty && !awaitsPasteControl {
                    empty
                } else {
                    list
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // **The two keys the panel took away, given back.** This row costs the
            // list one row of clips and costs the keyboard no height at all, which
            // is the same trade `EmojiCategoryRow` makes one panel over: both are
            // drawn inside the block the letter keys already occupy, so neither
            // goes anywhere near the 368 pt fingerprint cliff.
            CopyClipControlRow(
                height: keyHeight,
                isRightToLeft: controller.language.isRightToLeft,
                undoLabel: controller.revertibleEdit?.origin.undoLabel,
                onUndo: { controller.revertEdit() },
                onDelete: { controller.press(.backspace) },
                onDeleteRepeat: { controller.deletePreviousWord() }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Keys.background)
        .accessibilityIdentifier("copyclip-panel")
    }

    private var list: some View {
        // `List`, not `ScrollView` + `LazyVStack`: trailing swipe-to-delete is
        // a List row action. The spec forbade a grid, not a list. Plain style,
        // hidden separators, and zero content margins keep the cards looking
        // like letter keys rather than a settings table.
        List {
            if awaitsPasteControl {
                CopyClipPendingCaptureRow(controller: controller)
                    .listRowInsets(
                        EdgeInsets(
                            top: Theme.Metrics.keySpacing / 2,
                            leading: Theme.Metrics.sideInset,
                            bottom: Theme.Metrics.keySpacing / 2,
                            trailing: Theme.Metrics.sideInset)
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            ForEach(controller.clips) { clip in
                CopyClipCard(clip: clip) {
                    controller.insertClip(clip)
                } onDelete: {
                    controller.removeClip(id: clip.id)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        controller.removeClip(id: clip.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .listRowInsets(
                    EdgeInsets(
                        top: Theme.Metrics.keySpacing / 2,
                        leading: Theme.Metrics.sideInset,
                        bottom: Theme.Metrics.keySpacing / 2,
                        trailing: Theme.Metrics.sideInset)
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
        .contentMargins(.vertical, Theme.Metrics.keySpacing / 2, for: .scrollContent)
        .contentMargins(.horizontal, 0, for: .scrollContent)
    }

    private var empty: some View {
        VStack(spacing: Theme.Space.sm) {
            Image(systemName: "clipboard")
                .font(Theme.Glyph.font(28))
                .foregroundStyle(Theme.Keys.secondaryLabel)
            Text("Nothing copied yet")
                .font(Theme.Fonts.headline)
                .foregroundStyle(Theme.Keys.label)
            Text(emptyBody)
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.Keys.secondaryLabel)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Theme.Space.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyBody: String {
        var lines = ["Copy text in any app. It will show up here."]
        if SharedStore.shared.storage == .processLocal {
            lines.append("Allow Full Access so CopyClip can see what you copy.")
        }
        return lines.joined(separator: "\n")
    }
}

/// The row along the bottom of the panel: undo at one end, delete at the other.
///
/// **A panel that covers the letters has to carry whatever it covered that the
/// user still needs, and this one carried nothing.** The emoji grid worked that
/// out one file over — its category row pins a real delete key at the end,
/// "because this row replaces the letters while it is up, so it *is* the only
/// delete on screen" — and CopyClip has exactly the same shape with exactly the
/// same gap: a mistyped word behind the cursor could not be repaired without
/// closing the panel, and a clip tapped by accident could not be taken out at
/// all.
///
/// **A toolbar, not a key row, which is why the two ends are empty in the
/// middle.** The emoji row fills its width with ten category shortcuts and CopyClip
/// has no equivalent; two keys pushed together in the centre would read as a
/// fragment of a keyboard rather than as the panel's own controls. Splitting them
/// also buys the thing that matters most here: one of these removes a character
/// and the other removes an entire paste, so they are the two controls on this
/// panel that must never be hit for each other. Delete keeps the trailing end it
/// holds on every other row of this keyboard.
///
/// **Both keys wear the soft graphite cap, and the undo deliberately does not
/// take the brand tint its twin in the suggestion bar wears.** That is
/// `KeyView.actionTint`'s rule rather than an inconsistency: on a dark cap the
/// glyph is `labelOnFunction`, because a brand tint on soft graphite is neither
/// readable nor the neutral control the key is. The bar's revert sits on no cap
/// at all, so it can afford to be orange.
///
/// **Undo stays on the row when there is nothing to take back, and only fades.**
/// The suggestion bar's revert appears and disappears because there it is
/// competing with three candidate slots for 52 pt; here it competes with empty
/// panel, so the cost that bought that behaviour does not exist — and a control
/// nobody can see until the moment they have already made the mistake is one
/// nobody knows is there. It is the same answer Fix and Rewrite give over an
/// empty field: the cap stays, the label goes to
/// `KeyView.disabledLabelOpacity`, and the reason is said out loud for anyone who
/// cannot see the dim.
struct CopyClipControlRow: View {

    let height: CGFloat
    let isRightToLeft: Bool
    /// What the undo would take back, already named by
    /// `RevertibleEdit.Origin.undoLabel`. Nil is "nothing to take back", which is
    /// the only thing this row knows about the undo slot — it draws a Fix's way
    /// back exactly as it draws a paste's, because while this panel is up it is
    /// the only surface that can.
    let undoLabel: String?
    let onUndo: () -> Void
    let onDelete: () -> Void
    let onDeleteRepeat: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: 0) {
            undoKey
            Spacer(minLength: Theme.Space.sm)
            deleteKey
        }
        .frame(height: height)
        // The same margin `EmojiCategoryRow` takes, for the same reason: this row
        // is keys, and it lines up with the rhythm of the ones above rather than
        // running to the glass.
        .padding(.horizontal, Theme.Metrics.keySpacing)
        .animation(Theme.Motion.content, value: undoLabel)
    }

    private var undoKey: some View {
        KeyStyleButton(
            // The width that means "wide enough for a caption" on every other key
            // of this keyboard. Undo is the one control in the panel that is new,
            // and a lone arrow says nothing about what it puts back.
            width: KeyView.captionMinimumWidth, height: height,
            // `revertEdit()` fires its own haptic, exactly as `deleteBackward`
            // does for the key beside it.
            feedback: nil,
            restingCap: Theme.Keys.functionSoft,
            capKind: .soft,
            glyphColor: Theme.Keys.labelOnFunction,
            isDisabled: undoLabel == nil,
            action: onUndo
        ) {
            VStack(spacing: 1) {
                Image(systemName: "arrow.uturn.backward")
                    .font(Theme.Glyph.medium(15))
                Text("Undo")
                    .font(Font(SuggestionBar.toneLabelFont(for: dynamicTypeSize)))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .accessibilityIdentifier("copyclip-undo")
        .accessibilityLabel(undoLabel ?? "Undo")
        .accessibilityHint(
            undoLabel == nil ? "Nothing to take back yet" : "Puts back what you had written")
    }

    private var deleteKey: some View {
        KeyStyleButton(
            width: 42, height: height, repeats: true,
            repeatAction: onDeleteRepeat,
            // No `Feedback` call of its own: the delete already fires one per
            // character, and the button's own press haptic on top of it made a
            // single tap buzz twice. Same as the emoji panel's copy of this key.
            feedback: nil,
            restingCap: Theme.Keys.functionSoft,
            capKind: .soft,
            glyphColor: Theme.Keys.labelOnFunction,
            action: onDelete
        ) {
            Image(systemName: KeyCap.backspaceSymbol(isRightToLeft: isRightToLeft))
                .font(Theme.Glyph.font(19))
        }
        .accessibilityIdentifier("copyclip-delete")
        .accessibilityLabel("Delete")
    }
}

/// The CopyClip search box, drawn where the three word candidates normally are.
///
/// Same height trade as `EmojiSearchField`: the box takes the suggestion bar
/// rather than adding a row. The ✕ while editing returns to the list.
public struct CopyClipBar: View {
    @ObservedObject var controller: KeyboardController

    var isEditing: Bool { controller.overlay == .copyclipSearch }

    @State private var caretVisible = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public var body: some View {
        HStack(spacing: Theme.Space.xs) {
            Image(systemName: "magnifyingglass")
                .font(Theme.Glyph.font(15))
                .foregroundStyle(Theme.Keys.secondaryLabel)

            content

            Spacer(minLength: 0)

            if isEditing {
                Button {
                    controller.show(.copyclip)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(Theme.Glyph.font(16))
                        .foregroundStyle(Theme.Keys.secondaryLabel)
                        .contentShape(Rectangle())
                }
                .pressable()
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Theme.Space.sm)
        .frame(maxWidth: .infinity)
        .frame(height: 36)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                .fill(Theme.Keys.letter)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if !isEditing { controller.show(.copyclipSearch) }
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("copyclip-search-field")
    }

    @ViewBuilder
    private var content: some View {
        if controller.copyclipQuery.isEmpty {
            Text("Search copied")
                .font(.system(size: 16, weight: .light))
                .foregroundStyle(Theme.Keys.secondaryLabel)
            caret
        } else {
            Text(controller.copyclipQuery)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Theme.Keys.label)
                .lineLimit(1)
            caret
        }
    }

    @ViewBuilder
    private var caret: some View {
        if isEditing {
            RoundedRectangle(cornerRadius: 1)
                .fill(Theme.Brand.solid)
                .frame(width: 2, height: 20)
                .opacity(caretVisible ? 1 : 0)
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(.easeInOut(duration: 0.6).repeatForever()) {
                        caretVisible = false
                    }
                }
        }
    }
}

/// Matches for a CopyClip search, in the band the action row normally occupies.
///
/// Same swap as `EmojiResultsStrip`: query, letters and results have to be on
/// screen at once, and 368 pt has room for exactly the bands that already exist.
struct CopyClipResultsStrip: View {
    @ObservedObject var controller: KeyboardController
    let height: CGFloat

    var body: some View {
        Group {
            if controller.clips.isEmpty {
                Text("Nothing copied yet")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.Keys.secondaryLabel)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            } else if !controller.copyclipQuery.isEmpty && controller.copyclipResults.isEmpty {
                Text("No clips for \u{201C}\(controller.copyclipQuery)\u{201D}")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.Keys.secondaryLabel)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            } else {
                strip(
                    controller.copyclipQuery.isEmpty
                        ? controller.clips : controller.copyclipResults)
            }
        }
        .frame(height: height)
        .environment(\.layoutDirection, .leftToRight)
    }

    private func strip(_ clips: [Clip]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Space.xs) {
                ForEach(clips) { clip in
                    Button {
                        controller.insertClip(clip)
                    } label: {
                        Text(clip.text.value)
                            .font(.system(size: height * 0.38))
                            .foregroundStyle(Theme.Keys.label)
                            .lineLimit(1)
                            .padding(.horizontal, Theme.Space.sm)
                            .frame(height: height)
                            .frame(
                                minWidth: height,
                                maxWidth: height * 3.5,
                                alignment: CopyClipCard.frameAlignment(for: clip.text.value)
                            )
                            .background(Theme.Keys.card)
                            .clipShape(
                                RoundedRectangle(cornerRadius: Theme.Radius.key, style: .continuous)
                            )
                            .multilineTextAlignment(CopyClipCard.alignment(for: clip.text.value))
                    }
                    .pressable(scale: 0.92)
                    .accessibilityLabel(clip.text.value)
                    .accessibilityHint("Inserts into the field")
                }
            }
        }
        .accessibilityIdentifier("copyclip-search-results")
    }
}

private struct CopyClipCard: View {
    let clip: Clip
    let onInsert: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onInsert) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.sm) {
                Text(clip.text.value)
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.Keys.label)
                    .lineLimit(2)
                    .multilineTextAlignment(Self.alignment(for: clip.text.value))
                    .frame(maxWidth: .infinity, alignment: Self.frameAlignment(for: clip.text.value))
                Text(clip.capturedAt, format: .relative(presentation: .named))
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Keys.secondaryLabel)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            .padding(.vertical, Theme.Space.xs)
            .padding(.horizontal, Theme.Space.sm)
            .frame(minHeight: Theme.Metrics.minTouchTarget, alignment: .center)
        }
        .buttonStyle(CopyClipCardStyle())
        .accessibilityLabel(clip.text.value)
        .accessibilityHint("Inserts into the field")
        .accessibilityAction(named: "Delete", onDelete)
    }

    /// Block alignment follows the clip's script, not the panel's LTR pin.
    /// Hebrew copied into an LTR list would otherwise sit on the left edge.
    static func alignment(for text: String) -> TextAlignment {
        isRightToLeft(text) ? .trailing : .leading
    }

    static func frameAlignment(for text: String) -> Alignment {
        isRightToLeft(text) ? .trailing : .leading
    }

    static func isRightToLeft(_ text: String) -> Bool {
        LanguageDetector.scripts(in: text).contains { $0.isRightToLeft }
    }
}

private struct CopyClipCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.key, style: .continuous)
                    .fill(configuration.isPressed ? Theme.Keys.letterPressed : Theme.Keys.card)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(Theme.Motion.press, value: configuration.isPressed)
    }
}

/// The row CopyClip draws instead of reading a fresh pasteboard generation.
///
/// Same card shell as `CopyClipCard` — `Theme.Keys.card`, `Theme.Radius.key`
/// — because the row sits in the same list, but it is not a `Button`: the
/// tap target inside it is `CopyClipPasteControl` itself, a system `UIControl`
/// wrapped for SwiftUI, and it is the one piece of this row `Theme` cannot
/// reach. Apple supplies the label ("Paste") and the icon; only the fill,
/// the text colour and the corner radius are tunable, and they are pulled
/// from the same palette the card beside it uses, not from iOS's default
/// blue.
private struct CopyClipPendingCaptureRow: View {
    @ObservedObject var controller: KeyboardController

    var body: some View {
        HStack(spacing: Theme.Space.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text("New copy waiting")
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.Keys.label)
                Text("Paste adds it here. No prompt.")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Keys.secondaryLabel)
            }
            Spacer(minLength: Theme.Space.sm)
            CopyClipPasteControl { text in
                controller.captureFromPasteControl(text)
            }
            .fixedSize()
        }
        .padding(.vertical, Theme.Space.xs)
        .padding(.horizontal, Theme.Space.sm)
        .frame(minHeight: Theme.Metrics.minTouchTarget, alignment: .center)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.key, style: .continuous)
                .fill(Theme.Keys.card)
        )
        .accessibilityElement(children: .contain)
    }
}
