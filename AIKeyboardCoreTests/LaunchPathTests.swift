import Combine
import XCTest

@testable import AIKeyboardCore
@testable import AIKeyboardShared

/// The work taken off the path between the keyboard being asked for and the keys
/// being drawn.
///
/// NIT-186's audit found `viewWillAppear` repeating most of `viewDidLoad`: two
/// full decodes of the learned-word store, five decodes of the stored layout,
/// three XPC calls to containermanagerd, and a `load()` that wrote back all
/// twenty-two values it had just read. Each test here pins one of the four
/// changes that removed some of it, and each is written to fail against the
/// build that still does the work.
final class LaunchPathTests: XCTestCase {

    // MARK: The App Group, asked once

    /// `SharedContainer.url` was a computed property making an XPC round trip to
    /// containermanagerd on every read, and `userDefaults` built a fresh
    /// `UserDefaults` on top of that. Three of those are on the cold launch path
    /// and one more is paid on **every committed word**, through
    /// `PersonalLanguageModel.generation`.
    ///
    /// Identity is the assertion because `UserDefaults(suiteName:)` hands back a
    /// **new object** each call — an unguarded version therefore fails this,
    /// while equality of contents would pass either way.
    ///
    /// The precondition is asserted rather than assumed: with the group out of
    /// reach both reads answer `.standard`, which is one object for a reason that
    /// has nothing to do with this cache, and the test would pass vacuously.
    func testTheSharedSuiteIsResolvedOnceRatherThanOnEveryRead() throws {
        try XCTSkipIf(
            SharedContainer.url == nil,
            "no App Group here, so both reads are `.standard` and prove nothing")
        let first = SharedContainer.userDefaults
        XCTAssertFalse(
            first === UserDefaults.standard, "the state under test is the suite, not the fallback")
        XCTAssertTrue(first === SharedContainer.userDefaults)
    }

    /// A resolved container does not move under a live process, so the URL is
    /// cached too. Nil deliberately is not — see `SharedContainer.url` — but that
    /// half cannot be exercised from here, because nothing in a test can revoke
    /// an entitlement.
    func testTheContainerURLIsStableAcrossReads() throws {
        try XCTSkipIf(SharedContainer.url == nil, "nothing resolved to be stable about")
        XCTAssertEqual(SharedContainer.url, SharedContainer.url)
    }

    // MARK: The learned-word store, decoded once

    private func writeStore(_ json: String, to url: URL) throws {
        try Data(json.utf8).write(to: url, options: .atomic)
    }

    /// Writes and then pins the modification date to a fixed value.
    ///
    /// **Both writes in a same-stamp test have to be pinned to the *same
    /// explicit* date, and pushing the second one back onto a date read off the
    /// filesystem does not work.** Measured on macOS 2026-08-22:
    /// `setAttributes(_:ofItemAtPath:)` does not round-trip a `Date` that came
    /// from `attributesOfItem`, so the forged stamp came back subtly different
    /// and the test failed against correct code. Pinning both writes to one
    /// constant applies whatever rounding there is identically to each.
    private func writeStore(_ json: String, to url: URL, pinnedTo date: Date) throws {
        try writeStore(json, to: url)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    /// Any fixed instant. Only its stability matters.
    private let pinnedDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("launch-path-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    /// **The saving itself, isolated down to the one byte that decides it.**
    ///
    /// The two payloads are the same length on purpose, so the only thing telling
    /// them apart is the modification date — which this puts back. A `reload()`
    /// that still reads unconditionally answers `bbb`; the one that stamps
    /// answers `aaa`, because as far as the filesystem can say nothing happened.
    ///
    /// This is the second full decode of `PersonalLanguageModel.json` leaving the
    /// cold launch path: `KeyboardController.init` constructs the store and
    /// `viewWillAppear` used to decode the identical bytes again a moment later.
    @MainActor
    func testAFileThatHasNotMovedIsNotDecodedAgain() throws {
        let url = try temporaryDirectory().appendingPathComponent("model.json")
        try writeStore(
            #"{"unigrams":{"en":{"aaa":9}},"bigrams":{}}"#, to: url, pinnedTo: pinnedDate)

        let model = PersonalLanguageModel(url: url)
        XCTAssertEqual(model.count(of: "aaa", in: .english), 9, "the fixture did not load")

        try writeStore(
            #"{"unigrams":{"en":{"bbb":9}},"bigrams":{}}"#, to: url, pinnedTo: pinnedDate)

        model.reload()
        XCTAssertEqual(model.count(of: "aaa", in: .english), 9)
        XCTAssertEqual(model.count(of: "bbb", in: .english), 0)
    }

    /// The other half, and the one that would be a real defect if the stamp were
    /// too eager: the app writes the file, so a keyboard iOS kept alive has to
    /// see it. Identical to the test above except that the date is left where the
    /// write put it.
    @MainActor
    func testAFileTheAppRewroteIsPickedUpByAReload() throws {
        let url = try temporaryDirectory().appendingPathComponent("model.json")
        try writeStore(#"{"unigrams":{"en":{"aaa":9}},"bigrams":{}}"#, to: url)

        let model = PersonalLanguageModel(url: url)
        XCTAssertEqual(model.count(of: "aaa", in: .english), 9, "the fixture did not load")

        try writeStore(#"{"unigrams":{"en":{"bbb":9}},"bigrams":{}}"#, to: url)

        model.reload()
        XCTAssertEqual(model.count(of: "bbb", in: .english), 9)
        XCTAssertEqual(model.count(of: "aaa", in: .english), 0)
    }

    /// **Forget is the case the stamp could quietly break**, which is why it has
    /// its own test rather than being folded into the one above.
    ///
    /// Forget deletes the file in the app, and a keyboard still alive in another
    /// process must drop the counts rather than keep them. An absent file has no
    /// stamp, so a guard written as "skip when the stamp has not changed" would
    /// compare nil against nil and keep yesterday's words forever. The guard is
    /// written to require a stamp before it may skip.
    @MainActor
    func testForgettingTheFileEmptiesAStoreThatHadAlreadyLoadedIt() throws {
        let url = try temporaryDirectory().appendingPathComponent("model.json")
        try writeStore(#"{"unigrams":{"en":{"aaa":9}},"bigrams":{}}"#, to: url)

        let model = PersonalLanguageModel(url: url)
        XCTAssertEqual(model.count(of: "aaa", in: .english), 9, "the fixture did not load")

        try FileManager.default.removeItem(at: url)
        model.reload()
        XCTAssertEqual(model.count(of: "aaa", in: .english), 0)

        // And again, now that the stamp is nil on both sides. The version that
        // compares two nils and returns early passes the line above and fails
        // here only if it also kept the store — so assert on a fresh write
        // instead, which is what a Forget followed by more typing looks like.
        try writeStore(#"{"unigrams":{"en":{"ccc":4}},"bigrams":{}}"#, to: url)
        model.reload()
        XCTAssertEqual(model.count(of: "ccc", in: .english), 4)
    }

    // MARK: The layout, published once

    /// `customization` is `@Published`, and `apply` is called twice before the
    /// first frame with the same stored bytes — once from `KeyboardController.init`
    /// and once from `reloadCustomization()` in `viewWillAppear`. Each assignment
    /// fires `KeyboardView`'s observation and the extension's `$customization`
    /// sink, which is `.receive(on: RunLoop.main)`, so the second one bought a
    /// runloop hop and a redundant `updateKeyboardHeight()`.
    ///
    /// Counting emissions is the assertion because the *value* is identical
    /// either way: `@Published` sends on subscribe, so one is the floor and the
    /// unguarded build reaches two without the layout having changed.
    @MainActor
    func testApplyingTheSameLayoutTwiceDoesNotPublishItTwice() {
        let controller = KeyboardController(target: MockTextTarget(text: ""))
        var emissions = 0
        var bag = Set<AnyCancellable>()
        controller.$customization.sink { _ in emissions += 1 }.store(in: &bag)
        XCTAssertEqual(emissions, 1, "`@Published` sends the current value on subscribe")

        controller.apply(controller.customization)
        XCTAssertEqual(emissions, 1)

        var moved = controller.customization
        moved.showsNumberRow.toggle()
        controller.apply(moved)
        XCTAssertEqual(emissions, 2, "a layout that actually moved still has to reach the keys")
    }

    /// **The dangerous version of this cache is the one that decodes once and
    /// never again**, and that is the half this asserts hardest.
    ///
    /// The layout was decoded five times before the keyboard's first frame, each
    /// run costing a `JSONDecoder`, the preset refresh, the globe repair and
    /// `LayoutValidator`. Holding the answer against the bytes it came from
    /// removes four of them — and must not remove the fifth, because the editor
    /// is in the app and the keyboard is a second process, so different bytes
    /// have to mean a real decode or a layout the user just saved never reaches
    /// the keys.
    ///
    /// Counting decodes rather than comparing values, because a broken cache
    /// returning a stale value and a working one returning the same value are
    /// indistinguishable from the outside.
    func testADecodeIsHeldForTheSameBytesAndRedoneForDifferentOnes() {
        let cache = StoredDecode<Int>()
        var decodes = 0
        let first = Data("one".utf8)
        let second = Data("two".utf8)

        XCTAssertEqual(
            cache.value(for: first) {
                decodes += 1; return 1
            }, 1)
        XCTAssertEqual(decodes, 1)

        XCTAssertEqual(
            cache.value(for: first) {
                decodes += 1; return 99
            }, 1,
            "the same bytes were decoded a second time")
        XCTAssertEqual(decodes, 1)

        XCTAssertEqual(
            cache.value(for: second) {
                decodes += 1; return 2
            }, 2,
            "a setting the app changed never reached this process")
        XCTAssertEqual(decodes, 2)

        // An absent key is a value like any other. It is both a real change from
        // the bytes above and, once taken, worth holding: deciding "there is no
        // stored layout" walks the same preset table as deciding it once.
        XCTAssertEqual(
            cache.value(for: nil) {
                decodes += 1; return 3
            }, 3)
        XCTAssertEqual(decodes, 3)
        XCTAssertEqual(
            cache.value(for: nil) {
                decodes += 1; return 99
            }, 3)
        XCTAssertEqual(decodes, 3)
    }

    // MARK: The settings store, read without writing

    /// `load()`'s doc comment claimed for its whole life that it read "without
    /// firing the `didSet` writes above". `didSet` fires on every assignment
    /// outside `init`, so each load wrote back all twenty-two values it had just
    /// read, twice per cold launch.
    ///
    /// Driven through `persist` against a throwaway key rather than through
    /// `load()`, because `load()` is on the singleton and the singleton's
    /// defaults are the App Group plist, which is nobody's fixture.
    func testAWriteIsSuppressedWhileALoadIsTheOneAssigning() {
        let store = SharedStore.shared
        let key = "LaunchPathTests-\(UUID().uuidString)"
        addTeardownBlock {
            store.isLoading = false
            store.userDefaults.removeObject(forKey: key)
        }

        store.isLoading = true
        store.persist(42, forKey: key)
        XCTAssertNil(
            store.userDefaults.object(forKey: key),
            "a load wrote back the value it had just read")

        store.isLoading = false
        store.persist(42, forKey: key)
        XCTAssertEqual(
            store.userDefaults.integer(forKey: key), 42,
            "an ordinary setting change still has to persist")
    }
}
