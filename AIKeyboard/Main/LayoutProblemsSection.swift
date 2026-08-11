import AIKeyboardCore
import SwiftUI

/// Validation issues from the editor model, shown only when there are any.
struct LayoutProblemsSection: View {
    @ObservedObject var model: LayoutEditorModel

    var body: some View {
        let issues = model.issues
        if !issues.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                SectionHeader(title: "Problems")
                Card {
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
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
                }
            }
            .accessibilityIdentifier("layout-problems")
        }
    }
}
