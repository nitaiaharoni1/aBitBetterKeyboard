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

    public static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }

    /// The settings store the app and both extensions share, or this process's
    /// own when the group is out of reach.
    ///
    /// `SharedStore` wraps this with the typed accessors and the
    /// `.appGroup`/`.processLocal` report. The broadcast upload extension reads
    /// it directly, because `SharedStore` reaches `Feedback` and therefore UIKit,
    /// and that process must not link UIKit.
    public static var userDefaults: UserDefaults {
        guard url != nil, let suite = UserDefaults(suiteName: appGroupIdentifier) else {
            return .standard
        }
        return suite
    }
}
