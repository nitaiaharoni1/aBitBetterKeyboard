import AIKeyboardCore
import SwiftUI

// MARK: - Idle pill

/// The compact field that floats above the tab bar on every screen. Tapping it
/// opens the overlay, because a field that lives under the keyboard is a field
/// the user cannot see what they type into.
struct AppSearchIdlePill: View {
    @EnvironmentObject private var search: AppSearch

    var body: some View {
        Button {
            search.present()
        } label: {
            HStack(spacing: Theme.Space.xs) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.Text.tertiary)

                Text("Search")
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.Text.tertiary)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Space.sm)
            .padding(.vertical, 12)
            .contentShape(Capsule())
            .appSearchGlass(in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("app-search")
        .accessibilityLabel("Search")
    }
}

// MARK: - Overlay

struct AppSearchOverlay: View {
    @Binding var selection: MainTab
    @EnvironmentObject private var search: AppSearch
    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            Theme.Surface.background.opacity(0.94)
                .ignoresSafeArea()
                .onTapGesture(perform: search.dismiss)

            VStack(spacing: Theme.Space.sm) {
                field
                if search.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Spacer()
                } else {
                    results
                }
            }
            .padding(.horizontal, Theme.Space.md)
            .padding(.top, Theme.Space.sm)
        }
        .onAppear { focused = true }
    }

    private var field: some View {
        HStack(spacing: Theme.Space.xs) {
            HStack(spacing: Theme.Space.xs) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.Text.tertiary)

                TextField("Screens, settings, languages", text: $search.query)
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.Text.primary)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($focused)
                    .accessibilityIdentifier("app-search-field")

                if !search.query.isEmpty {
                    Button {
                        search.query = ""
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
            .padding(.vertical, 12)
            .appSearchGlass(in: Capsule())

            Button("Cancel", action: search.dismiss)
                .font(Theme.Fonts.body.weight(.medium))
                .foregroundStyle(Theme.Brand.solid)
        }
    }

    private var results: some View {
        let hits = search.results
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if hits.isEmpty {
                    Text("Nothing matches \u{201C}\(search.query)\u{201D}.")
                        .font(Theme.Fonts.callout)
                        .foregroundStyle(Theme.Text.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Theme.Space.md)
                } else {
                    ForEach(Array(hits.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Divider.themed.padding(.leading, 46) }
                        resultRow(item)
                    }
                }
            }
            .appSearchGlass(
                in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            )
        }
        .scrollDismissesKeyboard(.immediately)
    }

    private func resultRow(_ item: AppSearchItem) -> some View {
        Button {
            search.open(item, selection: $selection)
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
            .padding(.horizontal, Theme.Space.sm)
            .padding(.vertical, Theme.Space.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("app-search-result-\(item.id)")
    }
}

// MARK: - Glass

extension View {
    /// Liquid Glass on iOS 26, the existing raised-card language everywhere
    /// else. Chrome, not a brand fill: orange stays on AI moments.
    @ViewBuilder
    func appSearchGlass<S: InsettableShape>(in shape: S) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(.regular.interactive(), in: shape)
        } else {
            self
                .background(shape.fill(.ultraThinMaterial))
                .overlay(shape.strokeBorder(Theme.Surface.separator, lineWidth: 1))
                .shadow(color: Theme.Depth.color, radius: 16, y: 8)
        }
    }
}
