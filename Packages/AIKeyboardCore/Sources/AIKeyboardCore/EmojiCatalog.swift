import Foundation

/// One tab of the emoji grid.
public struct EmojiCategory: Identifiable, Sendable, Equatable {
    public let id: String
    /// SF Symbol drawn in the category row.
    public let icon: String
    public let emoji: [String]
}

/// Emoji as plain Unicode, with the words that find them.
///
/// **Generated, not hand-written.** `Scripts/generate-emoji-catalog.py` builds
/// `Resources/EmojiCatalog.json` from Unicode's `emoji-test.txt` (which emoji
/// exist, in which group, in what order) and CLDR's annotations (what each one is
/// called in English and Hebrew, and what else people search for it by). The
/// hand-picked list this replaced held 470 of the 1,870 and had no names at all,
/// so there was nothing for a search box to match against.
///
/// Nothing is bundled as an image. The system renders whatever the user's iOS
/// draws, so the app stays small and an emoji looks like it does everywhere else
/// on the phone.
///
/// **The generator caps the Emoji version at 15.0, and that cap is the reason
/// this grid has no tofu in it.** iOS 17.0 is `Package.swift`'s floor and shipped
/// Emoji 15.0; anything newer draws as a dotted box on a phone that has not been
/// updated, which is a key that looks broken rather than a key that is missing.
///
/// **Skin tones are beside the strip rather than in it.** The 1,870 in
/// `categories` carry no tone modifier at all; the five toned spellings of the
/// 304 that have any live in `tones`, which nothing scrolls past and only a held
/// cell reaches. Putting them in the strip would make the People tab six times
/// longer and would mean scrolling past five copies of every hand to reach the
/// next gesture. See `variants(for:)`.
public enum EmojiCatalog {

    /// The Recent tab. Not a category in the data: its contents are the user's,
    /// and they live in `KeyboardController.recentEmoji`.
    public static let recentID = "Recent"
    public static let recentIcon = "clock"

    /// Every category, in the order the row draws them.
    public static var categories: [EmojiCategory] { loaded.categories }

    /// Every emoji, in category order — the one long strip the grid lays out and
    /// the list search scans.
    public static var all: [String] { loaded.all }

    /// What this emoji is called, lowercased, one entry per locale. Empty for an
    /// emoji CLDR had no annotation for, which is none of them today.
    public static func names(for emoji: String) -> [String] {
        loaded.entries[emoji]?.names ?? []
    }

    /// The other words that should find it, lowercased and space-separated.
    public static func keywords(for emoji: String) -> String {
        loaded.entries[emoji]?.keywords ?? ""
    }

    /// Position in `all`. The tiebreak when two emoji score the same in search,
    /// so equally good matches come back in the order the grid shows them.
    public static func order(of emoji: String) -> Int {
        loaded.entries[emoji]?.order ?? Int.max
    }

    /// Which category an emoji belongs to, so the category row can highlight the
    /// tab the grid has been scrolled to.
    public static func category(of emoji: String) -> String? {
        loaded.entries[emoji]?.category
    }

    // MARK: Skin tones

    /// What a held cell offers: the emoji as Unicode draws it with no modifier,
    /// then its five tones light to dark. Empty for an emoji that has none,
    /// which is 1,566 of the 1,870.
    ///
    /// **Six entries or none, never a short row.** The generator only records a
    /// strip when all five toned spellings are fully qualified inside the version
    /// cap (`tone_variants`), so there is no emoji here whose picker would have a
    /// hole in it — and no phone on iOS 17 that draws one of these as tofu.
    ///
    /// Takes a toned spelling as happily as an untoned one, because the thing
    /// being held is whatever the grid drew, which is already wearing the user's
    /// tone. `untoned(_:)` is what makes that work.
    public static func variants(for emoji: String) -> [String] {
        let base = untoned(emoji)
        guard let toned = loaded.tones[base] else { return [] }
        return [base] + toned
    }

    /// Whether holding this cell offers anything, without building the row to
    /// find out. Asked once per visible cell per layout pass, which is why it is
    /// two dictionary reads rather than `!variants(for:).isEmpty`.
    public static func hasTones(_ emoji: String) -> Bool {
        loaded.tones[untoned(emoji)] != nil
    }

    /// The same emoji with no tone modifier on it — the spelling the grid, the
    /// recents and the search index are all keyed by. Anything this catalogue has
    /// never heard of comes back unchanged.
    public static func untoned(_ emoji: String) -> String {
        loaded.untoned[emoji] ?? emoji
    }

    /// The same emoji wearing `tone`, or unchanged if it has no strip.
    ///
    /// **The one place display and insertion agree.** The strip is stored
    /// untoned and the user's tone is applied at the moment a cell is drawn and
    /// again at the moment it is inserted; nothing in between stores a toned
    /// string, so changing the tone re-paints 304 cells without touching a
    /// single stored list.
    public static func toned(_ emoji: String, _ tone: EmojiSkinTone) -> String {
        let base = untoned(emoji)
        guard tone != .generic, let toned = loaded.tones[base] else { return base }
        let index = tone.rawValue - 1
        guard index >= 0, index < toned.count else { return base }
        return toned[index]
    }

    /// Which tone this spelling is wearing. `.generic` for everything untoned,
    /// which includes every emoji that has no strip at all.
    public static func tone(of emoji: String) -> EmojiSkinTone {
        guard let base = loaded.untoned[emoji], base != emoji,
            let index = loaded.tones[base]?.firstIndex(of: emoji)
        else { return .generic }
        return EmojiSkinTone(rawValue: index + 1) ?? .generic
    }

    /// Why the catalogue is empty, or nil when it loaded. Read by
    /// `EmojiCatalogTests`, which is the only thing standing between a resource
    /// that failed to copy and a keyboard that silently shows an empty grid.
    public static var loadFailure: String? { loaded.failure }

    // MARK: Loading

    struct Entry {
        let names: [String]
        let keywords: String
        let order: Int
        let category: String
    }

    struct Loaded {
        var categories: [EmojiCategory] = []
        var all: [String] = []
        var entries: [String: Entry] = [:]
        /// Untoned emoji -> its five toned spellings, light to dark. Only the
        /// 304 that have them.
        var tones: [String: [String]] = [:]
        /// Every toned spelling -> the untoned one, built here rather than
        /// shipped: it is `tones` read backwards, and 1,520 more strings in the
        /// resource would be 1,520 more strings to keep in step with it.
        var untoned: [String: String] = [:]
        var failure: String?
    }

    /// Read once, on the first emoji tap of the process rather than at launch.
    /// 261 KB of JSON is a few milliseconds, and it is wasted on every session
    /// where the user never opens the grid.
    static let loaded: Loaded = load()

    private struct Payload: Decodable {
        struct Category: Decodable {
            let id: String
            let icon: String
            let emoji: [String]
        }
        let categories: [Category]
        let keywords: [String: String]
        /// Absent in version 1 of the file, so this decodes as empty rather
        /// than throwing — a keyboard with no tone strips still types.
        let tones: [String: [String]]?
    }

    static func load() -> Loaded {
        guard let url = Bundle.module.url(forResource: "EmojiCatalog", withExtension: "json") else {
            return Loaded(failure: "EmojiCatalog.json is not in the resource bundle")
        }
        do {
            let payload = try JSONDecoder().decode(Payload.self, from: Data(contentsOf: url))
            var result = Loaded()
            var order = 0
            for category in payload.categories {
                result.categories.append(
                    EmojiCategory(id: category.id, icon: category.icon, emoji: category.emoji))
                for emoji in category.emoji {
                    result.all.append(emoji)
                    // `name|name\tkeyword keyword`. The tab is what keeps names
                    // tellable from keywords, which is the whole of why searching
                    // "heart" answers ❤️ rather than the first emoji that merely
                    // has "heart" among its keywords. See `EmojiSearch.score`.
                    let blob = payload.keywords[emoji] ?? "\t"
                    let halves = blob.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
                    result.entries[emoji] = Entry(
                        names: halves.first.map {
                            $0.split(separator: "|").map(String.init)
                        } ?? [],
                        keywords: halves.count > 1 ? String(halves[1]) : "",
                        order: order,
                        category: category.id
                    )
                    order += 1
                }
            }
            result.tones = payload.tones ?? [:]
            for (base, toned) in result.tones {
                for variant in toned { result.untoned[variant] = base }
            }
            return result
        } catch {
            return Loaded(failure: "EmojiCatalog.json could not be read: \(error)")
        }
    }
}
