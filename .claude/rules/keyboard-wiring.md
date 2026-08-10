---
paths:
  - "**/KeyboardController.swift"
  - "AIKeyboardExtension/KeyboardViewController.swift"
  - "AIKeyboardUITests/**"
  - "AIKeyboard/Main/**"
  - "AIKeyboard/Onboarding/**"
---

# How the extension is wired to the host app

- **The in-app playground is not evidence that the keyboard works, and for the whole of development it was believed to be.** The first install on a real phone typed *nothing* — keys drew, animated and clicked, and not one character reached the host app. `KeyboardController.target` was `weak` and `KeyboardViewController` built its `ProxyTextTarget` in argument position, so nothing retained it past `viewDidLoad` and every mutation was `target?.insertText` against nil. The playground was unaffected because `KeyboardPreview` holds its `MockTextTarget` as a `@StateObject`. So: the target is strong (nothing conforming to `TextTarget` references the controller back, so no cycle), the proxy is re-resolved per call through a `weak`-captured input view controller (`textDocumentProxy` is replaced when the host swaps fields, and `unowned` would trap when `KeyView`'s key-repeat `Task` outlives an interrupted gesture), and `AIKeyboardUITests/KeyboardTypesIntoHostTests.swift` presses a key on the real extension over a real `UITextField` and reads the field back. Before that file existed, *nothing* in the repo exercised the extension's own wiring — `AppGroupCrossProcessTests` and `CaptureChannelCrossProcessTests` already stood the extension over that exact field and asserted only that a key *existed*.
- **Never hand store-derived state to a pushed `NavigationLink` destination inside a `ScrollView`.** Destinations there are rebuilt on every parent body evaluation, so `LayoutView(layout: store.keyboardLayout)` made the *pushed* editor a function of the store — and its Done button writes the store, so it rebuilt the screen the user was standing on while that screen dismissed itself. The app pinned a core at 100% with an **empty accessibility tree**, which reads as a crash from the outside and leaves no crash report: four UI tests timed out and only the one that never tapped Done passed. The editor takes no parameters and reads `storedKeyboardLayout` once in `.task`. Same file, same class of bug, second instance: anything expensive in a `View.init` runs on every one of those rebuilds, so `LayoutView`'s `KeyboardController` is a `@StateObject` *property initialiser* (an autoclosure, deferred) rather than an assignment to `_canvas` inside `init`, which is not.
