import SwiftUI
import AIKeyboardCore

enum MainTab: Hashable {
    case home
    case languages
    case keys
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

            KeysView()
                .tabItem { Label("Keys", systemImage: "keyboard.fill") }
                .tag(MainTab.keys)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(MainTab.settings)
        }
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
}
