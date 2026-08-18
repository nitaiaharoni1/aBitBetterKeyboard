#!/usr/bin/env python3
"""Regenerate `Resources/EmojiCatalog.json` from Unicode and CLDR.

Two sources, both fetched live so a rerun tracks upstream rather than a copy
that rots here:

  * `emoji-test.txt` gives the ordering, the group each emoji belongs to and
    the Emoji version that introduced it. Unicode's own order is what every
    other keyboard shows, so it is what a thumb expects.
  * CLDR `annotations` and `annotationsDerived` give the words people search
    by, per locale. English and Hebrew are what this keyboard types.

Two filters, and both are load-bearing:

  * **Emoji version is capped** (`MAX_EMOJI_VERSION`). An emoji newer than the
    oldest iOS this package supports renders as a tofu box, which is worse than
    being absent — it is a key that looks broken. iOS 17.0 shipped Emoji 15.0,
    and iOS 17.0 is `Package.swift`'s floor.
  * **Skin-tone and hair components are dropped from the grid**, and kept to
    one side in `tones`. Five toned copies of every person would be five
    sixths of the catalogue, so the strip stays untoned and a long press on a
    cell is what reaches a tone — see `EmojiCatalog.variants(for:)`.

Run: python3 Scripts/generate-emoji-catalog.py
"""

import json
import pathlib
import re
import sys
import urllib.request

# iOS 17.0, this package's deployment target, shipped Emoji 15.0. Raising this
# without raising `Package.swift`'s `platforms` puts tofu on the grid.
MAX_EMOJI_VERSION = 15.0

EMOJI_TEST = "https://unicode.org/Public/emoji/15.1/emoji-test.txt"
CLDR = "https://raw.githubusercontent.com/unicode-org/cldr/main/common"
LOCALES = ("en", "he")

# Unicode's group names on the left, ours on the right, in the order the
# category bar draws them. Deliberately not Unicode's order: this is the order
# the shipped panel already had, and the tab bar is a row a thumb learns.
GROUPS = [
    ("Smileys & Emotion", "Smileys", "face.smiling"),
    ("People & Body", "People", "hand.raised"),
    ("Animals & Nature", "Nature", "leaf"),
    ("Food & Drink", "Food", "fork.knife"),
    ("Activities", "Activity", "figure.run"),
    ("Travel & Places", "Travel", "car"),
    ("Objects", "Objects", "lightbulb"),
    ("Symbols", "Symbols", "heart"),
    ("Flags", "Flags", "flag"),
]

# Light to dark, Fitzpatrick 1-2 through 6, which is the order every other
# keyboard draws the row in.
SKIN_TONE_ORDER = (0x1F3FB, 0x1F3FC, 0x1F3FD, 0x1F3FE, 0x1F3FF)
SKIN_TONES = set(SKIN_TONE_ORDER)
VARIATION_SELECTOR = "️"

# Keeps the file honest about its size. Nobody scrolls past the eighth word of
# a match list, and the tail of CLDR's keyword lists is where the noise is.
MAX_KEYWORDS_PER_LOCALE = 8


def pack(names: "list[str]", keywords: "list[str]") -> str:
    """One searchable string per emoji: `name|name<TAB>keyword keyword ...`.

    **The split between the two halves is what makes search usable rather than
    merely working.** Every emoji with a heart in it carries the keyword
    "heart", so a flat bag of words answers "heart" with 💘 and "לב" with 🥰 —
    correct, and not what anybody meant. Ranking a *name* match above a
    *keyword* match puts ❤️ first, and that ordering is only possible if the
    reader can still tell which words were the name. See `EmojiSearch.score`.

    Lowercased here rather than in the keyboard, so no search lowercases 1,900
    strings on its first keystroke.

    **The names are positional and are therefore never deduplicated against each
    other**, even when two locales say the same word. `EmojiCatalog.names(for:)`
    hands back this list in `LOCALES` order and `EmojiModeTests` reads slot 1 as
    the Hebrew one, so collapsing a pair would not shorten a list — it would
    move Hebrew into slot 0 and leave the emoji looking as though it had no
    Hebrew name at all. CLDR does produce them: 📀's Hebrew `tts` is now the
    Latin string "dvd", the same as English's. Only keywords are deduplicated,
    and only against the names, where the list is a bag of words and position
    means nothing.
    """
    seen: "set[str]" = set()
    unique_names: "list[str]" = []
    for name in names:
        folded = name.lower().strip()
        if folded:
            seen.add(folded)
            unique_names.append(folded)

    unique_keywords: "list[str]" = []
    for keyword in keywords:
        folded = keyword.lower().strip()
        # A keyword that merely repeats the name earns nothing and costs bytes.
        if folded and folded not in seen:
            seen.add(folded)
            unique_keywords.append(folded)

    if "|" in "".join(unique_names) or "\t" in "".join(unique_names + unique_keywords):
        raise ValueError("separator leaked into CLDR data")
    return "|".join(unique_names) + "\t" + " ".join(unique_keywords)


def fetch(url: str) -> str:
    with urllib.request.urlopen(url, timeout=60) as response:
        return response.read().decode("utf-8")


class EmojiTest:
    """What `emoji-test.txt` says, split into the two things this script needs.

    `by_group` is the grid: untoned, capped, in file order. `qualified` is every
    fully-qualified sequence in the file that is inside the cap, toned ones
    included, keyed by its codepoints — which is what `tone_variants` looks a
    candidate up in rather than trusting a rule.
    """

    def __init__(self) -> None:
        self.by_group: "dict[str, list[str]]" = {}
        self.qualified: "dict[tuple, str]" = {}
        # Every codepoint some sequence in the file puts a tone modifier
        # directly after — Unicode's `Emoji_Modifier_Base`, read off the data
        # rather than fetched as a second file.
        self.modifier_bases: "set[int]" = set()


def parse_emoji_test(text: str) -> EmojiTest:
    result = EmojiTest()
    group = ""
    line_pattern = re.compile(
        r"^([0-9A-F ]+?)\s*;\s*(\S+)\s*#\s*(\S+)\s+E(\d+\.\d+)\s"
    )
    for line in text.splitlines():
        if line.startswith("# group:"):
            group = line.split(":", 1)[1].strip()
            continue
        if line.startswith("#") or not line.strip():
            continue
        match = line_pattern.match(line)
        if not match:
            continue
        codepoints, status, emoji, version = match.groups()
        points = tuple(int(p, 16) for p in codepoints.split())
        for index, point in enumerate(points):
            if point in SKIN_TONES and index > 0:
                result.modifier_bases.add(points[index - 1])
        # Only `fully-qualified`. The other statuses are the same emoji spelled
        # without its variation selector; keeping them would double the grid
        # with characters that render identically.
        if status != "fully-qualified":
            continue
        if float(version) > MAX_EMOJI_VERSION:
            continue
        result.qualified[points] = emoji
        if set(points) & SKIN_TONES:
            continue
        result.by_group.setdefault(group, []).append(emoji)
    return result


def tone_variants(emoji: str, test: EmojiTest) -> "list[str]":
    """The five toned spellings of one untoned emoji, or `[]` if it has none.

    **Every one is looked up, none is constructed.** The rule — insert the
    modifier after each `Emoji_Modifier_Base` codepoint, swallowing a U+FE0F
    that followed it — is only how the *candidate* is spelled; what ships is
    the string `emoji-test.txt` gives for it, and a candidate the file does not
    fully-qualify inside the cap is dropped. That is the difference between a
    tone strip and five tofu boxes, and it is not theoretical: 👨‍👩‍👦 has three
    modifier bases in it and no toned form at all below Emoji 16.

    **All five or none.** A partial row would be a picker with holes in it, and
    the reader would have to guess whether a gap meant "not yet" or "never".
    Across the 1,870 in the grid there is in fact no partial case today — 304
    take all five and the rest take none — so this rejects a future upstream
    change rather than trimming today's data.
    """
    points = tuple(ord(character) for character in emoji)
    if not set(points) & test.modifier_bases:
        return []
    variants: "list[str]" = []
    for tone in SKIN_TONE_ORDER:
        candidate: "list[int]" = []
        index = 0
        while index < len(points):
            point = points[index]
            candidate.append(point)
            if point in test.modifier_bases:
                candidate.append(tone)
                # U+FE0F asks for the emoji presentation, and a tone modifier
                # already says it. Unicode spells ☝🏻 without one, so keeping it
                # would build a sequence the file has never heard of.
                if index + 1 < len(points) and points[index + 1] == 0xFE0F:
                    index += 1
            index += 1
        found = test.qualified.get(tuple(candidate))
        if found is None:
            return []
        variants.append(found)
    return variants


def parse_annotations(text: str, into: "dict[str, dict]", locale: str) -> None:
    """CLDR annotations into `{emoji: {"name": str, "keywords": [str]}}`.

    Keys are normalised by dropping U+FE0F, because CLDR strips it from every
    `cp` attribute while `emoji-test.txt` keeps it. Looking up "❤️" in a file
    that spells it "❤" silently finds nothing, which is exactly the kind of
    miss that leaves search working in English and dead in Hebrew.
    """
    pattern = re.compile(
        r'<annotation cp="([^"]+)"(?:\s+type="(\w+)")?\s*>(.*?)</annotation>',
        re.DOTALL,
    )
    for cp, kind, body in pattern.findall(text):
        key = cp.replace(VARIATION_SELECTOR, "")
        body = body.strip()
        if not body:
            continue
        entry = into.setdefault(key, {})
        if kind == "tts":
            entry.setdefault(f"name-{locale}", body)
        else:
            words = [w.strip() for w in body.split("|") if w.strip()]
            entry.setdefault(f"keywords-{locale}", words[:MAX_KEYWORDS_PER_LOCALE])


def main() -> int:
    print(f"fetching {EMOJI_TEST}")
    test = parse_emoji_test(fetch(EMOJI_TEST))
    by_group = test.by_group

    annotations: "dict[str, dict]" = {}
    for locale in LOCALES:
        for folder in ("annotations", "annotationsDerived"):
            url = f"{CLDR}/{folder}/{locale}.xml"
            print(f"fetching {url}")
            parse_annotations(fetch(url), annotations, locale)

    categories = []
    blobs: "dict[str, str]" = {}
    tones: "dict[str, list[str]]" = {}
    missing_hebrew = 0
    total = 0

    for unicode_name, our_id, icon in GROUPS:
        emoji = by_group.get(unicode_name, [])
        if not emoji:
            print(f"error: no emoji for group {unicode_name!r}", file=sys.stderr)
            return 1
        categories.append({"id": our_id, "icon": icon, "emoji": emoji})
        for character in emoji:
            total += 1
            entry = annotations.get(character.replace(VARIATION_SELECTOR, ""), {})
            names: "list[str]" = []
            keywords: "list[str]" = []
            for locale in LOCALES:
                name = entry.get(f"name-{locale}")
                if name:
                    names.append(name)
                keywords.extend(entry.get(f"keywords-{locale}", []))
            if not entry.get("name-he") and not entry.get("keywords-he"):
                missing_hebrew += 1
            blobs[character] = pack(names, keywords)
            variants = tone_variants(character, test)
            if variants:
                tones[character] = variants

    payload = {
        # 2 added `tones`. `EmojiCatalog` does not read this field — it is here
        # so a file found in a diff says what shape it is.
        "version": 2,
        "generator": "Scripts/generate-emoji-catalog.py",
        "maxEmojiVersion": MAX_EMOJI_VERSION,
        "categories": categories,
        "keywords": blobs,
        "tones": tones,
    }

    out = (
        pathlib.Path(__file__).resolve().parent.parent
        / "Packages/AIKeyboardCore/Sources/AIKeyboardCore/Resources/EmojiCatalog.json"
    )
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(
        json.dumps(payload, ensure_ascii=False, separators=(",", ":")), encoding="utf-8"
    )

    size = out.stat().st_size
    print(f"\nwrote {out.relative_to(out.parents[5])}")
    print(f"  {total} emoji across {len(categories)} categories, {size / 1024:.0f} KB")
    print(f"  {missing_hebrew} with no Hebrew words ({missing_hebrew / total:.1%})")
    print(f"  {len(tones)} with a skin tone strip")
    if missing_hebrew / total > 0.1:
        print("error: Hebrew coverage too thin to ship", file=sys.stderr)
        return 1
    # The People group alone is nearly 300 of them. A handful means the
    # modifier-base set came back empty and every strip was silently dropped,
    # which reads downstream as "no emoji has tones" rather than as a failure.
    if len(tones) < 200:
        print(f"error: only {len(tones)} emoji have tone strips", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
