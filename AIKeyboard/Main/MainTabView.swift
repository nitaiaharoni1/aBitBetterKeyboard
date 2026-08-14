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

    var body: some View {
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
