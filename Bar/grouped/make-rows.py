#!/usr/bin/env python3
"""Extract the shipped letter rows out of `LetterLayouts.swift` into JSON.

**Generated, never hand-written, and that is the whole point.** The grouped-key
harness derives every key grouping from these rows, so a row edited in Swift has
to move the harness with it. `LetterLayouts.hebrewMarks` is generated from
`hebrewRows` for exactly this reason — a row edit must not be able to leave a
letter behind.

This parses Swift with regular expressions, which is fragile on purpose: every
assertion below is written so a refactor that moves the rows **fails loudly**
rather than quietly emitting stale data. A harness measuring a layout the app no
longer ships is worse than one that will not run.

    python3 Bar/grouped/make-rows.py

Writes `Bar/grouped/data/rows.json`.
"""

import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SOURCE = REPO / "Packages/AIKeyboardCore/Sources/AIKeyboardCore/LetterLayouts.swift"
OUT = Path(__file__).resolve().parent / "data" / "rows.json"

# The 26 Latin letters and the 27 Hebrew glyphs, spelled out so the assertions
# below compare against something independent of what the parse returned.
LATIN = set("abcdefghijklmnopqrstuvwxyz")
HEBREW = set("אבגדהוזחטיכלמנסעפצקרשתךםןףץ")

# Hebrew's five final forms, which are positionally determined: a word may only
# end in one, and may only *not* end in its ordinary twin. `SeedLanguageModel`
# folds these already, for edit distance.
FINAL_FORMS = {"ך": "כ", "ם": "מ", "ן": "נ", "ף": "פ", "ץ": "צ"}


def quoted_strings(fragment: str) -> list[str]:
    return re.findall(r'"([^"]*)"', fragment)


def extract(text: str, pattern: str, what: str) -> list[str]:
    match = re.search(pattern, text)
    if not match:
        sys.exit(
            f"FAILED: no match for {what} in {SOURCE.name}.\n"
            f"  pattern: {pattern}\n"
            "  The Swift source moved. Fix this parser rather than the assertion —\n"
            "  a harness that silently keeps the old rows measures a keyboard\n"
            "  nobody ships."
        )
    rows = quoted_strings(match.group(1))
    if len(rows) != 3:
        sys.exit(f"FAILED: {what} gave {len(rows)} rows, expected 3: {rows}")
    return rows


def check(rows: list[str], expected: set[str], what: str) -> None:
    letters = "".join(rows)
    got = set(letters)
    if len(letters) != len(got):
        duplicates = sorted({c for c in letters if letters.count(c) > 1})
        sys.exit(f"FAILED: {what} repeats {duplicates}")
    if got != expected:
        missing = sorted(expected - got)
        extra = sorted(got - expected)
        sys.exit(f"FAILED: {what} missing={missing} extra={extra}")


def main() -> None:
    text = SOURCE.read_text(encoding="utf-8")

    english = extract(text, r"\.english:\s*LetterLayout\(\s*\[([^\]]*)\]", "English rows")
    hebrew = extract(text, r"static let hebrewRows\s*=\s*\[([^\]]*)\]", "hebrewRows")

    check(english, LATIN, "English")
    check(hebrew, HEBREW, "Hebrew")

    payload = {
        "generated_by": "Bar/grouped/make-rows.py",
        "source": "Packages/AIKeyboardCore/Sources/AIKeyboardCore/LetterLayouts.swift",
        "note": (
            "Physical key order, which is already Apple's left-to-right screen "
            "order. Right-to-left layouts are NOT mirrored here — see "
            ".claude/rules/keyboard-layout.md, where reading this as logical "
            "order reversed six languages at once."
        ),
        "languages": {
            "en": {"rows": english, "letters": sum(len(r) for r in english)},
            "he": {
                "rows": hebrew,
                "letters": sum(len(r) for r in hebrew),
                "finalForms": FINAL_FORMS,
            },
        },
    }

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print(f"wrote {OUT.relative_to(REPO)}")
    for tag, block in payload["languages"].items():
        print(f"  {tag}: {block['letters']} letters  {block['rows']}")


if __name__ == "__main__":
    main()
