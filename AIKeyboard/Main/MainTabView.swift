import AIKeyboardCore
import SwiftUI
import UIKit

enum MainTab: Hashable {
    case home
    case languages
    case keys
    case settings
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
        .background(TabTransitionDisabler())
        .environment(\.selectedMainTab, selection)
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

private struct TabTransitionDisabler: UIViewControllerRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> ProbeViewController {
        ProbeViewController { controller in
            context.coordinator.attach(from: controller)
        }
    }

    func updateUIViewController(_ controller: ProbeViewController, context: Context) {
        DispatchQueue.main.async { [weak controller, weak coordinator = context.coordinator] in
            guard let controller, let coordinator else { return }
            coordinator.attach(from: controller)
        }
    }

    static func dismantleUIViewController(
        _ controller: ProbeViewController, coordinator: Coordinator
    ) {
        coordinator.dismantle()
    }

    final class Coordinator: NSObject {
        private let delegate = TabBarDelegateProxy()
        private weak var tabBarController: UITabBarController?
        private var isDismantled = false

        func attach(from controller: UIViewController) {
            guard !isDismantled, controller.parent != nil else { return }
            guard let tabBarController = findTabBarController(from: controller) else { return }
            guard
                self.tabBarController !== tabBarController
                    || tabBarController.delegate !== delegate
            else { return }

            detach()
            delegate.previousDelegate = tabBarController.delegate
            tabBarController.delegate = delegate
            self.tabBarController = tabBarController
        }

        func dismantle() {
            isDismantled = true
            detach()
        }

        func detach() {
            guard let tabBarController else { return }
            if tabBarController.delegate === delegate {
                tabBarController.delegate = delegate.previousDelegate
            }
            delegate.previousDelegate = nil
            self.tabBarController = nil
        }

        private func findTabBarController(
            from controller: UIViewController
        )
            -> UITabBarController?
        {
            var ancestor: UIViewController? = controller
            while let current = ancestor {
                if let tabBarController = current as? UITabBarController {
                    return tabBarController
                }
                ancestor = current.parent
            }

            return findTabBarController(in: controller.viewIfLoaded?.window?.rootViewController)
        }

        private func findTabBarController(
            in controller: UIViewController?
        )
            -> UITabBarController?
        {
            guard let controller else { return nil }
            if let tabBarController = controller as? UITabBarController {
                return tabBarController
            }
            for child in controller.children {
                if let tabBarController = findTabBarController(in: child) {
                    return tabBarController
                }
            }
            return findTabBarController(in: controller.presentedViewController)
        }
    }

    final class ProbeViewController: UIViewController {
        private let attach: (UIViewController) -> Void

        init(attach: @escaping (UIViewController) -> Void) {
            self.attach = attach
            super.init(nibName: nil, bundle: nil)
            view.isUserInteractionEnabled = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) is unavailable")
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            attach(self)
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            attach(self)
        }
    }
}

/// Swaps the page instead of letting iOS animate it.
///
/// **A zero-duration `UIViewControllerAnimatedTransitioning` is the wrong tool
/// here, measured rather than assumed.** It swaps the page out of band while
/// UIKit still runs its own pass, and the recording of that build shows the
/// target tab, then the tab you left, then the target again. Taking the
/// selection instead means there is one swap and nothing to animate.
private final class TabBarDelegateProxy: NSObject, UITabBarControllerDelegate {
    weak var previousDelegate: UITabBarControllerDelegate?

    func tabBarController(
        _ tabBarController: UITabBarController, shouldSelect viewController: UIViewController
    ) -> Bool {
        if previousDelegate?.tabBarController?(tabBarController, shouldSelect: viewController)
            == false
        {
            return false
        }
        guard
            let index = tabBarController.viewControllers?.firstIndex(of: viewController),
            index != tabBarController.selectedIndex
        else { return false }

        // Assigning `selectedIndex` does not consult this method again, and it
        // does call `didSelect`, which is what carries the change back into
        // SwiftUI's `TabView` selection binding.
        UIView.performWithoutAnimation {
            tabBarController.selectedIndex = index
        }
        return false
    }

    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || previousDelegate?.responds(to: selector) == true
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        if previousDelegate?.responds(to: selector) == true {
            return previousDelegate
        }
        return super.forwardingTarget(for: selector)
    }
}
