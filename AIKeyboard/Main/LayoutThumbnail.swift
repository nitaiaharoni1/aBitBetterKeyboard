import SwiftUI
import AIKeyboardCore

/// A wireframe of a layout, small enough to compare five of them at a glance.
///
/// Drawn from the layout rather than from an asset, so a preset cannot end up
/// with a picture that no longer matches it.
struct LayoutThumbnail: View {
    let layout: KeyboardCustomization

    var body: some View {
        GeometryReader { geo in
            let gap: CGFloat = 2
            let rows = CGFloat(layout.rowCount)
            let height = max(2, (geo.size.height - gap * (rows - 1)) / rows)
            VStack(spacing: gap) {
                if layout.showsNumberRow { bar(count: 10, height: height) }
                bar(count: 10, height: height)
                bar(count: 9, height: height)
                bar(count: 9, height: height)
                bar(count: layout.bottomRow.count, height: height)
                if !layout.cursorRow.isEmpty { bar(count: layout.cursorRow.count, height: height) }
            }
            .frame(width: geo.size.width * layout.geometry.reach.widthFraction)
            .frame(maxWidth: .infinity, alignment: alignment)
            // Pinned for the same reason `KeyboardView.reachAlignment` is:
            // `.leading` resolves against the ambient layout direction, so on a
            // Hebrew system a thumbnail for `.left` reach would hug the physical
            // right edge. Not reachable today, because every shipped preset is
            // `.full` — one preset away from being the seventh time this repo
            // mirrored something that should not mirror.
            .environment(\.layoutDirection, .leftToRight)
        }
        .accessibilityHidden(true)
    }

    private var alignment: Alignment {
        switch layout.geometry.reach {
        case .full: return .center
        case .left: return .leading
        case .right: return .trailing
        }
    }

    private func bar(count: Int, height: CGFloat) -> some View {
        HStack(spacing: 1.5) {
            ForEach(0..<max(1, count), id: \.self) { _ in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Theme.Text.secondary.opacity(0.35))
            }
        }
        .frame(height: height)
    }
}
