import AIKeyboardCore
import SwiftUI
import UIKit

enum MainTab: Hashable, CaseIterable {
    case home
    case languages
    case keys
    case settings

    var title: String {
        switch self {
        case .home: "Home"
        case .languages: "Languages"
        case .keys: "Keys"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house.fill"
        case .languages: "globe"
        case .keys: "keyboard.fill"
        case .settings: "gearshape.fill"
        }
    }
}

/// Whether a pushed screen has claimed the whole window.
///
/// **The tab bar below is a plain `safeAreaInset`, not a `TabView`'s, so
/// `.toolbar(.hidden, for: .tabBar)` on a pushed destination does exactly
/// nothing.** The layout editor set it and believed it; the glass capsule went
/// on sitting over the editor's spare-key tray, cutting the last row of keys in
/// half and swallowing the taps that landed on them. A pushed full-window editor
/// sets this instead, and `MainTabBar` removes itself, inset and all.
///
/// **`@Observable` rather than `ObservableObject`, and that is the point of
/// using it.** A view that only *writes* this from `onAppear` never reads it in
/// `body`, so it takes no dependency and is not re-rendered — which matters
/// here, because `LayoutView` is a `NavigationLink` destination inside a
/// `ScrollView` and is already rebuilt on every Keys tab body evaluation. Only
/// `MainTabBar`, which reads it, redraws.
@MainActor
@Observable
final class AppChrome {
    var hidesTabBar = false
}

private struct SelectedMainTabKey: EnvironmentKey {
    static let defaultValue = MainTab.home
}

extension EnvironmentValues {
    var selectedMainTab: MainTab {
        get { self[SelectedMainTabKey.self] }
        set { self[SelectedMainTabKey.self] = newValue }
    }
}

struct MainTabView: View {
    @Binding var selection: MainTab
    @EnvironmentObject private var search: AppSearch

    var body: some View {
        ZStack {
            tab(.home) { HomeView() }
            tab(.languages) { LanguagesView() }
            tab(.keys) { KeysView() }
            tab(.settings) { SettingsView() }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            MainTabBar(selection: $selection)
        }
        .environment(\.selectedMainTab, selection)
        .animation(nil, value: selection)
        .onChange(of: search.pendingTab) { _, tab in
            guard let tab else { return }
            selection = tab
            search.pendingTab = nil
        }
        .onChange(of: selection) { _, _ in
            // Filtering Arabic on Languages must not follow you to Home as a
            // results list that hides the playground card. Jumps already
            // cleared the query in `open()`.
            if search.pendingTab == nil {
                search.dismiss()
            }
        }
    }

    /// Pages stay mounted. `TabView` is the system crossfade, and that is the flicker.
    private func tab<Content: View>(
        _ tab: MainTab, @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .opacity(selection == tab ? 1 : 0)
            .allowsHitTesting(selection == tab)
            .accessibilityHidden(selection != tab)
    }
}

private struct MainTabBar: View {
    @Binding var selection: MainTab
    @Environment(AppChrome.self) private var chrome

    /// Removed rather than hidden: an `EmptyView` measures zero, so the bottom
    /// safe-area inset collapses with it and the screen underneath gets the
    /// height back. Opacity would leave a 60 pt hole above the home indicator.
    var body: some View {
        if !chrome.hidesTabBar {
            bar
        }
    }

    private var bar: some View {
        HStack(spacing: 0) {
            ForEach(MainTab.allCases, id: \.self) { tab in
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 17, weight: .semibold))
                        Text(tab.title)
                            .font(Theme.Fonts.micro)
                    }
                    .foregroundStyle(selection == tab ? Theme.Brand.solid : Theme.Text.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Space.xs)
                    .background {
                        if selection == tab {
                            Capsule().fill(Theme.Brand.solid.opacity(0.12))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selection == tab ? [.isSelected] : [])
            }
        }
        .background { TabBarAccessibilityProbe() }
        .padding(Theme.Space.xxs)
        .tabBarGlass()
        .padding(.horizontal, Theme.Space.md)
        .padding(.bottom, -Theme.Space.sm)
    }
}

private extension View {
    @ViewBuilder
    func tabBarGlass() -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            self.background(.ultraThinMaterial, in: Capsule())
        }
    }
}

/// XCUITest finds `app.tabBars.buttons["Languages"]` on a real tab bar trait.
private struct TabBarAccessibilityProbe: UIViewRepresentable {
    func makeUIView(context: Context) -> TabBarTraitView {
        TabBarTraitView()
    }

    func updateUIView(_ view: TabBarTraitView, context: Context) {
        view.apply()
    }
}

private final class TabBarTraitView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        apply()
    }

    func apply() {
        guard let superview else { return }
        superview.accessibilityTraits.insert(.tabBar)
        superview.isAccessibilityElement = false
    }
}
