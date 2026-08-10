import SwiftUI

/// Lays its children out in a line and wraps, which `HStack` will not do and
/// which a row of chips needs the moment there are more than fit.
///
/// Lived in `LanguagesView` as a `private` type until the layout editor's Add
/// drawer needed the same thing. Moved here rather than copied: two of these
/// drift, and the second copy written from scratch already got
/// `sizeThatFits` wrong by returning an infinite width for an unconstrained
/// proposal, which collapses the scroll view around it.
struct FlowRow: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions().width
        let rows = arrange(subviews: subviews, in: width)
        let height = rows.reduce(CGFloat(0)) { $0 + $1.height + spacing }
        return CGSize(width: width, height: max(0, height - spacing))
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        var y = bounds.minY
        for row in arrange(subviews: subviews, in: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Line {
        var indices: [Int] = []
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, in width: CGFloat) -> [Line] {
        var lines: [Line] = []
        var current = Line()
        var x: CGFloat = 0
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !current.indices.isEmpty, x + size.width > width {
                lines.append(current)
                current = Line()
                x = 0
            }
            current.indices.append(index)
            current.height = max(current.height, size.height)
            x += size.width + spacing
        }
        if !current.indices.isEmpty { lines.append(current) }
        return lines
    }
}
