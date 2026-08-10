import SwiftUI
import AIKeyboardCore

struct MainTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }

            LanguagesView()
                .tabItem { Label("Languages", systemImage: "globe") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
    }
}
