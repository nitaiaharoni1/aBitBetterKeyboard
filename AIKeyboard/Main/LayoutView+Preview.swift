import SwiftUI
import AIKeyboardCore

#if DEBUG

#Preview {
    NavigationStack {
        LayoutView()
    }
    .environmentObject(SharedStore.shared)
    .environment(AppChrome())
}

#endif
