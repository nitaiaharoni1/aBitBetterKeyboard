#!/usr/bin/env python3
"""Schema check for `corpus.json`, run before the expensive part.

`AsyncTypingCorpusTests.swift`'s `CorpusEntry` is a strict `Decodable`: a
missing `id`, `category`, `keyboard`, `context` or `prefix`, or a `screen`
object missing one of its five fields, fails the whole test with no output
at all — after `xcodebuild` has already spent minutes building and booting.
This is the cheap half of that contract, checked in Python with no simulator,
so a malformed entry is caught before anything is spent on it.

    Bar/typing/async/validate.py

`score.py` is the other half: it reads `mustNotCorrect` / `intended` /
`acceptable` with `.get()`, so a typo'd key there does not raise, it just
silently drops the entry into the `unjudged` bucket forever. This checks that
every entry actually asks a question `score.py` can grade.
"""

from __future__ import annotations

import json
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
CORPUS = HERE / "corpus.json"

REQUIRED_STRING_FIELDS = ("id", "category", "keyboard", "context", "prefix")
SCREEN_FIELDS = ("appName", "appIcon", "sender", "message", "language")
VERDICT_KEYS = ("mustNotCorrect", "intended", "acceptable")


def check(corpus: dict) -> list[str]:
    problems: list[str] = []
    entries = corpus.get("entries")
    if not isinstance(entries, list) or not entries:
        return ["corpus has no entries"]

    seen_ids: set[str] = set()
    for index, entry in enumerate(entries):
        where = f"entries[{index}]"
        eid = entry.get("id")
        if isinstance(eid, str) and eid:
            where = f"entries[{index}] ({eid!r})"
            if eid in seen_ids:
                problems.append(f"{where}: duplicate id")
            seen_ids.add(eid)

        # Matches AsyncTypingCorpusTests.CorpusEntry exactly: every one of
        # these is non-optional there, so a missing one is not a soft failure
        # in Swift, it is JSONDecoder throwing before any entry runs.
        for field in REQUIRED_STRING_FIELDS:
            if not isinstance(entry.get(field), str):
                problems.append(f"{where}: missing or non-string {field!r}")

        pause = entry.get("pauseMs")
        if pause is not None and not isinstance(pause, int):
            problems.append(f"{where}: pauseMs must be an int or absent, got {pause!r}")

        screen = entry.get("screen")
        if screen is not None:
            if not isinstance(screen, dict):
                problems.append(f"{where}: screen must be an object")
            else:
                for field in SCREEN_FIELDS:
                    if not isinstance(screen.get(field), str):
                        problems.append(f"{where}: screen.{field} missing or non-string")

        # score.py's score() checks mustNotCorrect, then intended, then
        # acceptable, in that order, and stops at the first truthy one — so
        # an entry with two of these silently drops the second, and an entry
        # with none of them is graded as "unjudged" forever, counted nowhere
        # in the headline. Neither is ever what the corpus author meant.
        present = [key for key in VERDICT_KEYS if entry.get(key)]
        if not present:
            problems.append(f"{where}: has none of {VERDICT_KEYS} — score.py will call it unjudged")
        elif len(present) > 1:
            problems.append(
                f"{where}: has more than one of {present} — score.py only reads the first"
            )

        if entry.get("acceptable") is not None:
            acceptable = entry["acceptable"]
            if not isinstance(acceptable, list) or not acceptable or not all(
                isinstance(w, str) for w in acceptable
            ):
                problems.append(f"{where}: acceptable must be a non-empty list of strings")
            if not isinstance(entry.get("acceptableIsClosed"), bool):
                problems.append(f"{where}: acceptable is set but acceptableIsClosed is not a bool")

        language = entry.get("language")
        keyboard = entry.get("keyboard", "")
        if language == "he" and not keyboard.startswith("he"):
            problems.append(f"{where}: language he with keyboard {keyboard!r}")
        if language == "en" and not keyboard.startswith("en"):
            problems.append(f"{where}: language en with keyboard {keyboard!r}")

    return problems


def summarise(corpus: dict) -> None:
    entries = corpus["entries"]
    by_kind: dict[str, int] = {}
    by_language: dict[str, int] = {}
    paused = screened = 0
    for entry in entries:
        if entry.get("mustNotCorrect"):
            kind = "mustNotCorrect"
        elif entry.get("intended"):
            kind = "intended"
        elif entry.get("acceptable") is not None:
            kind = "acceptable-closed" if entry.get("acceptableIsClosed") else "acceptable-open"
        else:
            kind = "unjudged"
        by_kind[kind] = by_kind.get(kind, 0) + 1
        by_language[entry.get("language", "?")] = by_language.get(entry.get("language", "?"), 0) + 1
        if entry.get("pauseMs") is not None:
            paused += 1
        if entry.get("screen") is not None:
            screened += 1

    print(f"{len(entries)} entries, {paused} with a pause, {screened} with a screen")
    print("  by kind:     " + ", ".join(f"{k}={v}" for k, v in sorted(by_kind.items())))
    print("  by language: " + ", ".join(f"{k}={v}" for k, v in sorted(by_language.items())))


def main() -> None:
    corpus = json.loads(CORPUS.read_text(encoding="utf-8"))
    summarise(corpus)
    problems = check(corpus)
    if problems:
        print(f"\nFAILED {len(problems)}:", file=sys.stderr)
        for problem in problems:
            print(f"  !! {problem}", file=sys.stderr)
        sys.exit(1)
    print("\nvalidate: schema holds for every entry")


if __name__ == "__main__":
    main()
