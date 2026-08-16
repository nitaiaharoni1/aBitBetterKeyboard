// Just enough of the package for `EmojiSearch.swift` and `EmojiCatalog.swift`
// to compile on their own.
//
// **Nothing here is under test.** It is one accessor. `EmojiCatalog.load()`
// reads `Bundle.module`, which SwiftPM generates for a target with resources
// and `swiftc` does not, so without this the two files do not compile at all.
// It points at a bundle `swift-check.sh` assembles from the *shipping*
// `Resources/EmojiCatalog.json` — the same 233 KB the keyboard loads, not a
// fixture — because a fidelity check against a made-up catalogue proves the
// two implementations agree about data neither one ships.
import Foundation

extension Bundle {
    static let module: Bundle = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["EMOJI_RESOURCE_BUNDLE"],
            let bundle = Bundle(path: path)
        else {
            FileHandle.standardError.write(
                Data("EMOJI_RESOURCE_BUNDLE is unset or is not a bundle\n".utf8))
            exit(1)
        }
        return bundle
    }()
}
