import SwiftUI
import AIKeyboardCore

enum MainTab: Hashable {
    case home
    case languages
    case settings
}

struct MainTabView: View {
    @Binding var selection: MainTab
    @EnvironmentObject private var search: AppSearch

    var body: some View {
        TabView(selection: $selection) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(MainTab.home)

            LanguagesView()
                .tabItem { Label("Languages", systemImage: "globe") }
                .tag(MainTab.languages)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(MainTab.settings)
        }
        .safeAreaInset(edge: .bottom, spacing: Theme.Space.xs) {
            if !search.isPresented {
                AppSearchIdlePill()
                    .padding(.horizontal, Theme.Space.md)
                    .padding(.bottom, Theme.Space.xs)
            }
        }
        .overlay {
            if search.isPresented {
                AppSearchOverlay(selection: $selection)
            }
        }
    }
}
