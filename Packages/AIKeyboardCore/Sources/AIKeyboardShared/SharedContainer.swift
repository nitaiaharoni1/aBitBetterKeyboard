import Foundation

/// The App Group, and the only question about it that has a false answer.
///
/// `UserDefaults(suiteName:)` hands back a usable object whether or not this
/// process is entitled to the group, so it can only ever look like success.
/// `containerURL(forSecurityApplicationGroupIdentifier:)` is nil without the
/// entitlement, and nil in the keyboard until the user grants Full Access, which
/// is why every probe in this project goes through it.
///
/// **A file of its own, not part of `CaptureChannel`.** Three things now ask
/// where the shared container is and only one of them is the capture channel:
/// `SharedStore` reads the settings plist out of it, `BackendTransport` reads the
/// backend URL, and the channel maps its pages there. It is also the one piece
/// of this target that compiles on its own, with no `CaptureAtomics` behind it,
/// which is what lets `Bar/ai-text/harness/run-real.sh` build the real cloud
/// transport outside every target.
public enum SharedContainer {

    public static let appGroupIdentifier = "group.com.nitai.aikeyboard"

    /// Guards the two answers below.
    ///
    /// Both are read from the main thread, from the two utility queues
    /// `KeyboardViewController` dispatches its records on, and from the
    /// broadcast extension's own thread. `URL?` and a class reference are not
    /// the same width and neither is promised to be a single atomic store, so
    /// an unguarded static here would be a torn read rather than a stale one.
    private static let lock = NSLock()
    private static var resolvedURL: URL?
    private static var resolvedSuite: UserDefaults?

    /// Where the shared container is, asked once and then remembered.
    ///
    /// **A resolved container is cached and an unresolved one is not, and that
    /// asymmetry is the whole design.** Every read of this used to be an XPC
    /// round trip to containermanagerd. Three of them are on the keyboard's cold
    /// launch path before the first frame, and one more — through
    /// `PersonalLanguageModel.generation`, which `record(word:…)` consults — is
    /// paid on **every word the user commits**, for the life of the process.
    /// None of them can come back with a different answer once the answer is a
    /// URL: a granted container does not move under a live process.
    ///
    /// Nil is a different fact and is deliberately never cached, because this
    /// repo already relies on it changing mid-process. iOS grants a keyboard
    /// extension the group only when the user allows Full Access, and
    /// `KeyboardViewController.recordPresence()` is written to retry until the
    /// container takes the record precisely so a keyboard that starts without
    /// Full Access and is granted it while running still leaves one. Caching the
    /// nil would strand that keyboard on process-local storage for the rest of
    /// its life. The `if let` below is what keeps a nil from ever being a hit.
    ///
    /// **The revocation direction is a known limit rather than an oversight.**
    /// A user who turns Full Access *off* under a live keyboard keeps being
    /// handed the URL this resolved. That is already the behaviour of the one
    /// reader that matters most: `SharedStore` probes once in `init` and holds
    /// its suite in a `let`, so its `storage` report and every setting it serves
    /// have never noticed a revocation either. Everything reached through this
    /// URL is `try?` file I/O, so the failure mode is a write that silently does
    /// nothing — which is what `.processLocal` already looks like from outside.
    public static var url: URL? {
        lock.lock()
        defer { lock.unlock() }
        return unlockedURL()
    }

    /// The settings store the app and both extensions share, or this process's
    /// own when the group is out of reach.
    ///
    /// `SharedStore` wraps this with the typed accessors and the
    /// `.appGroup`/`.processLocal` report. The broadcast upload extension reads
    /// it directly, because `SharedStore` reaches `Feedback` and therefore UIKit,
    /// and that process must not link UIKit.
    ///
    /// Cached under the same rule as `url`, and for a second reason on top of
    /// the XPC call: `UserDefaults(suiteName:)` allocates and registers a fresh
    /// object every time, and this is the default argument of four
    /// `CloudTransport` entry points, so it was being built once per call rather
    /// than once per process. A cached suite is exactly as fresh as an
    /// uncached one — `SharedStore` has held its own in a `let` since the day it
    /// was written, and reading the app's writes from the keyboard is the
    /// premise the whole `stored*` family rests on. The `.standard` fallback is
    /// never cached, for the reason nil is not.
    public static var userDefaults: UserDefaults {
        lock.lock()
        defer { lock.unlock() }
        if let resolvedSuite { return resolvedSuite }
        guard unlockedURL() != nil, let suite = UserDefaults(suiteName: appGroupIdentifier) else {
            return .standard
        }
        resolvedSuite = suite
        return suite
    }

    /// The resolution itself, for the two callers that are already holding the
    /// lock. `NSLock` is not recursive, so `userDefaults` cannot simply read
    /// `url`, and `url` cannot keep a second copy of this without the two
    /// drifting.
    private static func unlockedURL() -> URL? {
        if let resolvedURL { return resolvedURL }
        let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier)
        resolvedURL = container
        return container
    }
}
