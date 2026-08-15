import AIKeyboardCore
import SwiftUI

/// One line per issue, no card and no heading. The dock already says these
/// belong to the layout; a "Problems" block was a third vertical section.
struct LayoutProblemsSection: View {
    @ObservedObject var model: LayoutEditorModel

    var body: some View {
        let issues = model.issues
        if !issues.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                ForEach(issues) { issue in
                    HStack(alignment: .top, spacing: Theme.Space.xs) {
                        Image(
                            systemName: issue.severity == .error
                                ? "exclamationmark.triangle.fill" : "info.circle"
                        )
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(
                            issue.severity == .error
                                ? Theme.Semantic.record : Theme.Semantic.warning)
                        Text(issue.message)
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.Text.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
            .accessibilityIdentifier("layout-problems")
            .accessibilityElement(children: .combine)
        }
    }
}
