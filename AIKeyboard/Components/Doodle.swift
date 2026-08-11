import SwiftUI
import AIKeyboardCore

// MARK: - The editor's pen
//
// Hand-drawn orange marks, translated from the approved mock's inline SVGs
// with the control-point wobble kept — a pen, not a compass. They annotate
// two or three marketing moments in the whole app (the onboarding headline,
// the home greeting, one empty state) and never appear on working surfaces.
//
// Every doodle is `Theme.Brand.action` and hidden from accessibility by
// construction: orange is the pen (red stays recording-only), and decoration
// must not be read out.

/// The circled key word, from the mock's "writes": a loop that overshoots
/// itself and does not quite close, with a fainter second pass underneath —
/// a pen going back over its own line. Stretches to its frame rather than
/// keeping its aspect, the way the mock's SVG sits at 112% by 136% of the
/// word it circles.
struct DoodleCircle: View {
    var body: some View {
        ZStack {
            DoodleCircleLoop()
                .stroke(Theme.Brand.action, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            DoodleCircleEcho()
                .stroke(
                    Theme.Brand.action.opacity(0.45),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        .accessibilityHidden(true)
    }
}

/// The wavy underline from the mock's section headline.
struct DoodleSwash: View {
    var body: some View {
        DoodleSwashPath()
            .stroke(Theme.Brand.action, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            .aspectRatio(300.0 / 22.0, contentMode: .fit)
            .accessibilityHidden(true)
    }
}

/// The curved arrow from the mock's stage. Drawn pointing down-trailing;
/// rotate at the call site to aim it.
struct DoodleArrow: View {
    var body: some View {
        DoodleArrowPath()
            .stroke(
                Theme.Brand.action,
                style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round)
            )
            .aspectRatio(100.0 / 90.0, contentMode: .fit)
            .accessibilityHidden(true)
    }
}

// MARK: - Paths
//
// Coordinates are the mock's SVG viewBox values mapped into `rect`, so the
// wobble scales with the frame. Stroke widths stay fixed on purpose: they
// are tuned for the small sizes the app places these at.

private struct DoodleCircleLoop: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x / 220 * rect.width, y: rect.minY + y / 80 * rect.height)
        }
        var path = Path()
        path.move(to: p(12, 44))
        path.addCurve(to: p(152, 10), control1: p(18, 14), control2: p(92, 4))
        path.addCurve(to: p(214, 50), control1: p(206, 16), control2: p(222, 34))
        path.addCurve(to: p(66, 70), control1: p(205, 69), control2: p(118, 76))
        path.addCurve(to: p(10, 42), control1: p(24, 65), control2: p(4, 58))
        return path
    }
}

private struct DoodleCircleEcho: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x / 220 * rect.width, y: rect.minY + y / 80 * rect.height)
        }
        var path = Path()
        path.move(to: p(16, 52))
        path.addCurve(to: p(182, 62), control1: p(40, 70), control2: p(130, 78))
        return path
    }
}

private struct DoodleSwashPath: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x / 300 * rect.width, y: rect.minY + y / 22 * rect.height)
        }
        var path = Path()
        path.move(to: p(4, 12))
        path.addCurve(to: p(296, 8), control1: p(70, 20), control2: p(180, 20))
        return path
    }
}

private struct DoodleArrowPath: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x / 100 * rect.width, y: rect.minY + y / 90 * rect.height)
        }
        var path = Path()
        path.move(to: p(8, 8))
        path.addCurve(to: p(82, 74), control1: p(30, 50), control2: p(55, 70))
        path.move(to: p(62, 60))
        path.addCurve(to: p(84, 78), control1: p(70, 66), control2: p(78, 72))
        path.addCurve(to: p(58, 82), control1: p(76, 78), control2: p(66, 80))
        return path
    }
}
