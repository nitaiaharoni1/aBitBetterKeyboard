import SwiftUI

/// Clipboard history over the letter keys. The action row stays.
///
/// Cards are letter keys, not a second chrome language: same fill, radius and
/// press as the caps they replaced. The list is vertical because fifty clips
/// are a scroll, not a grid. Search is the same swap emoji already makes:
/// this panel goes, the letters come back, and the action row becomes matches.
public struct CopyClipPanel: View {
    @ObservedObject var controller: KeyboardController

    public var body: some View {
        Group {
            if controller.clips.isEmpty {
                empty
            } else {
                list
            }
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
