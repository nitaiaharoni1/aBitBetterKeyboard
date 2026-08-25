#!/usr/bin/env python3
"""Expands typos.json into a corpus, and refuses to expand a mislabelled one.

    Bar/typing/typos/expand.py                    # writes to stdout
    Bar/typing/typos/expand.py /tmp/typos.json    # writes a file
    TYPOS_PAIRS=other.json Bar/typing/typos/expand.py

The output is `Bar/typing/corpus.json`'s own shape, so `harness/run.sh` runs it
with nothing changed and `harness/main.swift` decodes it as it stands: one entry
per pair, `prefix` is the misspelling and `intended` is the word the person meant.
`class` and `note` ride along for `judge.py`, and Swift's decoder ignores them.

**Half of this file is a validator, and that is the point.** A taxonomy nobody
checks is a set of labels somebody typed once: call a row `adjacent-1` when the
two letters are nowhere near each other and the report says the keyboard is bad
at fat fingers when it was never asked about one. Every class with a mechanical
shape is checked here against the rows this keyboard actually draws
(`LetterLayouts.hebrewRows`, by way of `KeyProximity`), and a row that does not
have the shape it claims fails the run rather than quietly widening a column.
The classes with no mechanical shape — `phonetic`, `clitic` past its prefix — say
so below rather than pretending to a check they cannot make.

The one place the check is looser than it looks is `transpose`, which compares
with the final forms folded onto their ordinary shapes. Swapping the last two
letters of a Hebrew word also changes the shape of one of them — `שלום` becomes
`שלמו`, not `שלוםמ` — so a strict character swap would reject the commonest
Hebrew transposition there is.
"""

import json
import os
import pathlib
import sys
import unicodedata
from datetime import datetime, timezone

HERE = pathlib.Path(__file__).resolve().parent

# `KeyProximity.rows`, which is itself `LetterLayouts.hebrewRows` written out.
# Copied rather than derived, for the same reason that Swift file copies it: the
# harness compiles `KeyProximity.swift` and not `KeyboardLayout.swift`, so this is
# already the second copy and not the first. `KeyProximityTests` pins the Swift
# side; a drift here shows up as a validator rejecting a pair that is fine.
ROWS = {
    "he": ["קראטוןםפ", "שדגכעיחלךף", "זסבהנמצתץ"],
    "en": ["qwertyuiop", "asdfghjkl", "zxcvbnm"],
}

# Ordinary shape -> final shape. Hebrew's five letters that change shape at the
# end of a word, and the whole of `final-form` / `final-form-wrong`.
FINALS = {"כ": "ך", "מ": "ם", "נ": "ן", "פ": "ף", "צ": "ץ"}
UNFINALS = {final: ordinary for ordinary, final in FINALS.items()}

# The letters Hebrew writes or omits depending on how full the spelling is.
MATRES = set("יוא")

# Letters that are one sound in modern Israeli Hebrew. Not a phonology: the
# groups people actually mix up in writing, which is why ק sits with כ (both /k/)
# while ח sits with כ (both /x/) and the two groups overlap on כ.
HOMOPHONES = [set("אהע"), set("חכ"), set("טת"), set("כק"), set("סש")]

# Hebrew's glued one-letter prefixes. `HebrewMorphology` knows the same seven.
CLITICS = set("הבלמושכ")

# class -> id fragment. Short, because the id is a column in judge.py's output and
# `he-must-not-correct-07` would push every line past a terminal width.
SLUGS = {
    "adjacent-1": "adj1",
    "adjacent-2": "adj2",
    "transpose": "trans",
    "final-form": "final",
    "final-form-wrong": "finalw",
    "mater-drop": "matdrop",
    "mater-add": "matadd",
    "homophone": "homo",
    "omit": "omit",
    "double": "dbl",
    "clitic": "clitic",
    "phonetic": "phon",
    "apostrophe": "apos",
    "must-not-correct": "nc",
    # `Bar/typing/typos/probes-motor2/` only, see `check` for the shape.
    "mater-drop-double": "matdrop2",
    "homophone-final": "homofin",
}


def pairs_path():
    if override := os.environ.get("TYPOS_PAIRS"):
        return pathlib.Path(override)
    return HERE / "typos.json"


def nfc(text):
    return unicodedata.normalize("NFC", text)


def shape_folded(text):
    """Final forms put back into their ordinary shape.

    `SuggestionEngine.hebrewShapeFolded` does the same thing for the same reason:
    a letter takes its ordinary shape the moment anything follows it, so two
    spellings of one word disagree on the code points and agree on the letters.
    """
    return "".join(UNFINALS.get(character, character) for character in text)


def position(letter, rows):
    for row, letters in enumerate(rows):
        column = letters.find(letter)
        if column >= 0:
            return row, column
    return None


def adjacent(first, second, language):
    """Same row at col±1, or a neighbouring row at col±1 with the diagonal
    included. Columns are compared as written, with no stagger.

    **This is `KeyProximity.areAdjacent`'s raw-index rule, and the Swift was
    being reworked into a geometry rule while this file was written**: rows of
    8, 10 and 9 keys are each centred inside the same reference width, so index
    7 of one row and index 7 of another are not above each other, and the new
    version compares normalised key centres instead. It drops fifteen Hebrew
    cross-row pairs and adds none.

    Every pair in `typos.json` is valid under both, which was checked rather
    than assumed: all but two of the substitutions are within one row, where the
    two rules are identical, and the two that are not clear the new threshold
    with room — ר/ד by 0.34 of a key width and ו/י by 0.84, against a floor of
    1. Keeping the looser rule here is deliberate. This is a question about
    fingers, not about the engine's opinion of them, and a validator that
    tracked the engine would start rejecting pairs for being *correctly*
    labelled the day the layout changed.
    """
    rows = ROWS[language]
    left, right = position(first.lower(), rows), position(second.lower(), rows)
    if left is None or right is None:
        return False
    row_gap, column_gap = abs(left[0] - right[0]), abs(left[1] - right[1])
    if row_gap == 0:
        return column_gap == 1
    return column_gap <= 1 if row_gap == 1 else False


def differences(typed, intended):
    """Indexes where two equal-length strings disagree."""
    return [i for i, (a, b) in enumerate(zip(typed, intended)) if a != b]


def deletions(longer, shorter):
    """Every index of `longer` whose removal yields `shorter`.

    Returned as a list rather than a bool because the class checks below need to
    know *what* was dropped: a dropped letter that equals its neighbour is a
    double, a dropped yod is a mater, and neither is a plain omission.
    """
    if len(longer) != len(shorter) + 1:
        return []
    return [i for i in range(len(longer)) if longer[:i] + longer[i + 1:] == shorter]


def double_deletions(longer, shorter):
    """Every pair of indexes in `longer` whose joint removal yields `shorter`.

    `deletions` one size up: `mater-drop-double`, in `Bar/typing/typos/probes-motor2/`,
    is two matres lectionis dropped from the same word rather than one, and the
    single-deletion helper above cannot see a length gap of two. Quadratic in the
    length of `longer`, which is a handful of Hebrew letters, not a performance
    question.
    """
    if len(longer) != len(shorter) + 2:
        return []
    out = []
    for i in range(len(longer)):
        for j in range(i + 1, len(longer)):
            if longer[:i] + longer[i + 1:j] + longer[j + 1:] == shorter:
                out.append((i, j))
    return out


def check(pair):
    """Why this row is not the class it claims, or None if it is.

    Every message says what was found as well as what was wanted, because the
    row that fails is nearly always a Hebrew string with one character wrong in a
    JSON file and "adjacent-1 wants one substitution" alone does not point at it.
    """
    typed, intended = nfc(pair["typed"]), nfc(pair["intended"])
    language, kind = pair["language"], pair["class"]
    same_length = len(typed) == len(intended)
    changed = differences(typed, intended) if same_length else None

    if kind == "must-not-correct":
        if typed != intended:
            return f"must-not-correct wants typed == intended, got {typed!r} / {intended!r}"
        return None

    if typed == intended:
        return f"{kind} is a misspelling class and both strings are {typed!r}"

    if kind in ("adjacent-1", "adjacent-2"):
        wanted = 1 if kind == "adjacent-1" else 2
        if not same_length:
            return f"{kind} wants a substitution, so the two words must be the same length"
        if len(changed) != wanted:
            return f"{kind} wants {wanted} substitution(s), found {len(changed)}"
        for index in changed:
            if not adjacent(typed[index], intended[index], language):
                return (
                    f"{typed[index]!r} and {intended[index]!r} are not neighbouring keys"
                    f" on the {language} layout (index {index})"
                )
        return None

    if kind == "transpose":
        # Folded, because the final form moves with the letter. See the module
        # docstring.
        left, right = shape_folded(typed), shape_folded(intended)
        if len(left) != len(right):
            return "transpose wants two words of the same length"
        moved = differences(left, right)
        if len(moved) != 2 or moved[1] != moved[0] + 1:
            return f"transpose wants two neighbouring positions to disagree, found {moved}"
        first, second = moved
        if not (left[first] == right[second] and left[second] == right[first]):
            return "the two disagreeing letters are not a swap of each other"
        return None

    if kind == "final-form":
        if not same_length or changed != [len(typed) - 1]:
            return "final-form wants exactly the last letter to differ"
        if FINALS.get(typed[-1]) != intended[-1]:
            return f"{typed[-1]!r} is not the ordinary shape of {intended[-1]!r}"
        return None

    if kind == "final-form-wrong":
        if not same_length or len(changed) != 1:
            return "final-form-wrong wants exactly one letter to differ"
        index = changed[0]
        if index == len(typed) - 1:
            return "a final form at the end of a word is correct, not this class"
        if UNFINALS.get(typed[index]) != intended[index]:
            return f"{typed[index]!r} is not the final shape of {intended[index]!r}"
        return None

    if kind in ("mater-drop", "mater-add"):
        longer, shorter = (intended, typed) if kind == "mater-drop" else (typed, intended)
        dropped = [i for i in deletions(longer, shorter) if longer[i] in MATRES]
        if not dropped:
            return (
                f"{kind} wants one of {''.join(sorted(MATRES))} added to or removed from"
                f" the other spelling; {typed!r} and {intended!r} do not differ that way"
            )
        return None

    if kind == "mater-drop-double":
        # `Bar/typing/typos/probes-motor2/` only: two matres lectionis dropped
        # from the same word, the double-slip counterpart of `mater-drop`
        # above. `double_deletions` is the two-index version of `deletions`.
        pairs = double_deletions(intended, typed)
        valid = [p for p in pairs if intended[p[0]] in MATRES and intended[p[1]] in MATRES]
        if not valid:
            return (
                f"mater-drop-double wants two of {''.join(sorted(MATRES))} removed from"
                f" {intended!r} to reach {typed!r}"
            )
        return None

    if kind == "homophone":
        if not same_length or len(changed) != 1:
            return "homophone wants exactly one letter to differ"
        index = changed[0]
        pair_of = {typed[index], intended[index]}
        if not any(pair_of <= group for group in HOMOPHONES):
            return f"{typed[index]!r} and {intended[index]!r} are not one sound in Hebrew"
        return None

    if kind == "homophone-final":
        # `Bar/typing/typos/probes-motor2/` only: a homophone substitution
        # stacked with a final-form substitution in the same word, the two
        # cheapest substitution rules `TypoChannel` has (40 and 20) landing on
        # one pair of keystrokes rather than each on its own.
        if not same_length or len(changed) != 2:
            return "homophone-final wants exactly two letters to differ"
        last = len(typed) - 1
        if last not in changed:
            return "homophone-final wants the last letter to be one of the two differences"
        other = changed[0] if changed[1] == last else changed[1]
        if FINALS.get(typed[last]) != intended[last]:
            return f"{typed[last]!r} is not the ordinary shape of {intended[last]!r}"
        pair_of = {typed[other], intended[other]}
        if not any(pair_of <= group for group in HOMOPHONES):
            return f"{typed[other]!r} and {intended[other]!r} are not one sound in Hebrew"
        return None

    if kind in ("omit", "double"):
        # `omit` has a direction and `double` does not: `untill` doubles a letter
        # that should appear once and `acommodate` writes one that should appear
        # twice, and both are the same mistake about the same rule.
        if kind == "omit":
            longer, shorter = intended, typed
        else:
            longer, shorter = max(typed, intended, key=len), min(typed, intended, key=len)
        dropped = deletions(longer, shorter)
        if not dropped:
            return f"{kind} wants the two spellings to differ by exactly one letter"
        # A letter dropped from beside its own twin is a doubling error, not an
        # omission, and the two classes would otherwise be the same test.
        doubles = any(
            (index > 0 and longer[index - 1] == longer[index])
            or (index + 1 < len(longer) and longer[index + 1] == longer[index])
            for index in dropped
        )
        if kind == "omit" and doubles:
            return "the missing letter sits beside its own twin, which is the `double` class"
        if kind == "double" and not doubles:
            return "the extra or missing letter is not beside a twin, which is `omit`"
        return None

    if kind == "apostrophe":
        if intended.replace("'", "").replace("’", "").lower() != typed.lower():
            return "apostrophe wants the same letters with the apostrophe left out"
        return None

    if kind == "clitic":
        # Only the prefix is checkable. What is *behind* it is a typo of some
        # other class, deliberately, and asserting which one would be a second
        # taxonomy inside this one.
        if intended[0] not in CLITICS:
            return f"{intended[0]!r} is not one of Hebrew's glued prefixes"
        return None

    if kind == "phonetic":
        # No shape to check: an English word spelled the way it sounds can differ
        # from the real spelling by anything at all. `seperate` is one
        # substitution and `definately` is two edits in different places.
        return None

    return f"unknown class {kind!r}"


def validate(source):
    taxonomy = source["taxonomy"]
    problems = []
    seen = set()
    for index, pair in enumerate(source["pairs"]):
        where = f"pair {index} ({pair.get('typed')!r} -> {pair.get('intended')!r})"
        missing = [key for key in ("typed", "intended", "language", "class", "note") if not pair.get(key)]
        if missing:
            problems.append(f"{where}: missing {', '.join(missing)}")
            continue
        if pair["language"] not in ROWS:
            problems.append(f"{where}: language must be he or en")
            continue
        if pair["class"] not in taxonomy:
            problems.append(f"{where}: class {pair['class']!r} is not in the taxonomy")
            continue
        if pair["class"] not in SLUGS:
            problems.append(f"{where}: class {pair['class']!r} has no id slug")
            continue
        # A Hebrew string under `"language": "en"` types on the wrong layout and
        # every answer after that is about a keyboard nobody was using.
        hebrew = any("֐" <= character <= "׿" for character in pair["typed"])
        if hebrew != (pair["language"] == "he"):
            problems.append(f"{where}: script and language disagree")
            continue
        key = (nfc(pair["typed"]), pair.get("context", ""))
        if key in seen:
            problems.append(f"{where}: the same input already appears in this file")
        seen.add(key)
        if problem := check(pair):
            problems.append(f"{where} [{pair['class']}]: {problem}")
    return problems


def expand(pairs):
    entries = []
    counts = {}
    for pair in pairs:
        language = pair["language"]
        slug = SLUGS[pair["class"]]
        counts[(language, slug)] = counts.get((language, slug), 0) + 1
        entries.append({
            "id": f"{language}-{slug}-{counts[(language, slug)]:02d}",
            "category": f"typo-{pair['class']}",
            "language": language,
            "keyboard": "he_IL" if language == "he" else "en_US",
            "context": pair.get("context", ""),
            "prefix": pair["typed"],
            "intended": pair["intended"],
            "class": pair["class"],
            "note": pair["note"],
            "probes": pair["note"],
        })
    return entries


def main():
    source = json.loads(pairs_path().read_text())
    if problems := validate(source):
        print(f"{pairs_path()}: {len(problems)} row(s) do not match the class they claim:",
              file=sys.stderr)
        for problem in problems:
            print(f"  {problem}", file=sys.stderr)
        return 1

    entries = expand(source["pairs"])
    corpus = {
        "schema": 1,
        "name": "Misspelling corpus (generated)",
        "generated": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "source": str(pairs_path()),
        "notes": (
            "Generated by Bar/typing/typos/expand.py. Not a frozen corpus and not a "
            "regression guard: edit typos.json and regenerate. The frozen exam is "
            "Bar/typing/corpus.json. `prefix` is the misspelling and `intended` is "
            "what the person meant; on a must-not-correct row they are the same "
            "string and any other commit is the failure."
        ),
        "entries": entries,
    }
    text = json.dumps(corpus, ensure_ascii=False, indent=2) + "\n"
    if len(sys.argv) > 1:
        pathlib.Path(sys.argv[1]).write_text(text)
        counted = {}
        for entry in entries:
            counted[entry["class"]] = counted.get(entry["class"], 0) + 1
        shape = ", ".join(f"{kind} {n}" for kind, n in sorted(counted.items()))
        print(f"{len(entries)} pairs -> {sys.argv[1]}\n  {shape}", file=sys.stderr)
    else:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
