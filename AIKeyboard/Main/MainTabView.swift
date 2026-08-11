import SwiftUI
import AIKeyboardCore

enum MainTab: Hashable {
    case home
    case languages
    case settings
}

struct MainTabView: View {
    @Binding var selection: MainTab

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
    }
}
