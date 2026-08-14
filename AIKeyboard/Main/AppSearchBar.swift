import AIKeyboardCore
import SwiftUI

struct PageTitle: View {
    var title: String

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Image("BrandMark")
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)
            Text(title)
                .font(Theme.Fonts.page)
                .tracking(-0.9)
                .foregroundStyle(Theme.Text.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .overlay(alignment: .bottom) {
                    DoodleSwash()
                        .frame(height: 8)
                        .offset(y: 5)
                }
        }
    }
}

/// Title plus the in-flow search field, shared by Home, Languages, Keys, and
/// Settings so the four headers stay one chrome.
struct AppSearchHeader: View {
    var title: String
    var searchAccessibilityID: String = "app-search"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                PageTitle(title: title)
                AppSearchField(fieldIdentifier: searchAccessibilityID)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Space.md)
            .padding(.vertical, Theme.Space.xxs)

            Rectangle()
                .fill(Theme.Surface.separator)
                .frame(height: 1)
                .frame(maxWidth: .infinity)
        }
        .background(Theme.Surface.background.opacity(0.96))
    }
}

/// The in-flow search field that sits under each tab's title. Same chrome as
/// the language catalogue field used to have: a raised rounded rect in the
/// header, not a pill that floats over the tab bar (and under the keyboard).
struct AppSearchField: View {
    var fieldIdentifier: String = "app-search"
    @EnvironmentObject private var search: AppSearch
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.Text.tertiary)

            TextField("Screens, settings, languages", text: $search.query)
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.Text.primary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($focused)
                .accessibilityIdentifier(fieldIdentifier)
                .accessibilityLabel("Search")
                .onSubmit { focused = false }

            if !search.query.isEmpty {
                Button {
                    search.dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.Text.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Theme.Space.sm)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.Surface.raised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.Surface.separator, lineWidth: 1)
        )
        .onChange(of: search.stackEpoch) { _, _ in focused = false }
        .onChange(of: search.resignFocus) { _, _ in focused = false }
    }
}

/// Replaces the tab's scrolling content while a query is in the field.
struct AppSearchResults: View {
    var includeLanguages = true
    var showsEmpty = true
    @EnvironmentObject private var search: AppSearch

    var body: some View {
        let hits = filteredHits
        Group {
            if hits.isEmpty {
                if showsEmpty {
                    Card(padding: Theme.Space.xs) {
                        Text("Nothing matches \u{201C}\(search.query)\u{201D}.")
                            .font(Theme.Fonts.callout)
                            .foregroundStyle(Theme.Text.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Theme.Space.sm)
                    }
                }
            } else {
                Card(padding: Theme.Space.xs) {
                    VStack(spacing: 0) {
                        ForEach(Array(hits.enumerated()), id: \.element.id) { index, item in
                            if index > 0 { Divider.themed.padding(.leading, 46) }
                            resultRow(item)
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("app-search-results")
    }

    private var filteredHits: [AppSearchItem] {
        guard !includeLanguages else { return search.results }
        return search.results.filter {
            if case .language = $0.destination { return false }
            return true
        }
    }

    private func resultRow(_ item: AppSearchItem) -> some View {
        Button {
            search.open(item)
        } label: {
            HStack(spacing: Theme.Space.sm) {
                if let flag = item.flag {
                    Text(flag)
                        .font(.system(size: 22))
                        .frame(width: 30, height: 30)
                } else {
                    IconBadge(systemName: item.icon)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(Theme.Fonts.body.weight(.medium))
                        .foregroundStyle(Theme.Text.primary)
                    Text(item.subtitle)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Text.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Space.xs)
            .padding(.vertical, Theme.Space.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("app-search-result-\(item.id)")
    }
}
