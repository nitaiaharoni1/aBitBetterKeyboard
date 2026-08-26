#!/usr/bin/env python3
"""Judges a misspelling corpus: does the bar offer the word, and does space take it?

    Bar/typing/typos/judge.py corpus.json run-1.json run-2.json
    Bar/typing/typos/judge.py corpus.json run-*.json --verbose

**The bold slot is the headline, because it is the only column that changes the
document.** `SuggestionEngine` pins the typed keystrokes into slot zero on
purpose, so "the right word is in the bar" stays true of an engine that has
stopped working — the scorer for the frozen 90 was wrong about exactly this and
mislabelled 40 of its 76 entries. `main.swift` writes `commits`, the text of the
slot marked default, which is what `KeyboardController.insertSpace` inserts.

Every row is one of four things, and the four are what the report is made of:

  committed  The bold slot holds the word the person meant. The keyboard fixed
             the typo.
  held       The bold slot holds what was typed. The keyboard declined. Never a
             defect on its own: this repo's engine deliberately refuses to commit
             a correction two dictionaries do not agree about, and over-correcting
             is what makes people switch autocorrect off.
  offered    The intended word is in a slot, whether or not space would take it.
             **Not one of the three verdicts** — it is asked of the same row
             alongside them, because it separates "the ranker put it second" from
             "no source ever generated it", which are different bugs with
             different fixes. It is counted over the slots `main.swift` recorded,
             which is the engine's array, and mid-word that array holds
             `SuggestionEngine.barSlots + 1` candidates while the bar draws three:
             `SuggestionBar.centeredSlots` puts the default in the middle, the
             next two either side, and drops the rest. So a word recorded at slot
             3 was generated and ranked and would still not have been on screen.
             The slot index is printed with every such row rather than modelled
             here, because a second spelling of `centeredSlots` in Python would
             drift from the one that draws the keyboard.
  WRONG      The bold slot holds a third word: not what was typed, not what was
             meant. **This is the column that matters most.** A keyboard that
             declines to help is inert; a keyboard that inserts a word nobody was
             reaching for is the reason autocorrect has the reputation it has.
             Every one of these is printed individually, always, and none of them
             is ever summarised into a total.

A `must-not-correct` row is a correctly spelled word, so `typed` and `intended`
are the same string and the three verdicts collapse into two: **intact** when the
bold slot still holds what was typed, WRONG for anything else. They are counted
apart from the corrections and they are the reason the headline cannot be gamed:
a build that corrects everything scores badly here instead of perfectly.

**One run is not evidence, so several are the argument the interface makes.**
Pass every run on the command line. A row only reaches the table when every run
agrees on both its verdict and the exact string it committed; anything that moved
gets its own heading and is counted nowhere. This is `sweep/judge.py`'s rule for
`sweep/judge.py`'s reason: `UITextChecker`'s Hebrew completion list is not stable
between runs, or even between two identical questions inside one run, and a
finding built on one Hebrew answer is a coin toss written up as a defect.
"""

import json
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
# `norm` is the frozen corpus's own normaliser: NFC, lowercased, quotes stripped,
# maqaf folded onto the ASCII hyphen and the curly apostrophe onto the straight
# one. A second spelling of it here would drift, and both halves of this repo's
# apostrophe bugs came from exactly that.
sys.path.insert(0, str(HERE.parent / "harness"))
import score  # noqa: E402

COMMITTED, HELD, WRONG, INTACT = "committed", "held", "WRONG", "intact"


def verdict(typed, commits, intended):
    """One row's verdict, all three strings already normalised.

    The control rows come first because on them `typed == intended`, and asking
    the correction questions in that order would report every untouched word as
    `committed` and make the controls unable to fail.
    """
    if typed == intended:
        return INTACT if commits == typed else WRONG
    if commits == intended:
        return COMMITTED
    if commits == typed:
        return HELD
    return WRONG


def judge(corpus, outputs):
    by_id = {entry["id"]: entry for entry in corpus["entries"]}
    rows = {}
    for record in outputs:
        entry = by_id.get(record["id"])
        if entry is None:
            continue
        typed = score.norm(entry["prefix"])
        intended = score.norm(entry["intended"])
        commits = score.norm(record["commits"])
        slots = [score.norm(slot) for slot in record["slots"]]
        visible = score.layer_set(record.get("visible"))
        generated = score.layer_set(record.get("generated"))
        control = typed == intended
        rows[record["id"]] = {
            "id": record["id"],
            "class": entry["class"],
            "language": entry["language"],
            "context": entry["context"],
            "typed": entry["prefix"],
            "intended": entry["intended"],
            "commits": record["commits"],
            "slots": record["slots"],
            "visible": record.get("visible"),
            "generated": record.get("generated"),
            "verdict": verdict(typed, commits, intended),
            "control": control,
            # Ranked array, including the fourth mid-word candidate. The drawn
            # row is `visibleOffered`. Kept so existing totals stay comparable.
            "offered": None if control else (intended in slots),
            "offeredAt": None if control or intended not in slots else slots.index(intended),
            "visibleOffered": None if control or visible is None else intended in visible,
            "generatedOffered": None if control or generated is None else intended in generated,
            # None rather than [] when the run predates the column, so a missing
            # measurement cannot be read as a clean one.
            "misspelled": record.get("misspelled"),
            "note": entry.get("note", ""),
        }
    return rows


def tally(rows):
    counts = {COMMITTED: 0, HELD: 0, WRONG: 0, INTACT: 0}
    offered = 0
    for row in rows:
        counts[row["verdict"]] += 1
        offered += bool(row["offered"])
    return counts, offered


def run_headline(rows, label):
    corrections = [row for row in rows.values() if not row["control"]]
    controls = [row for row in rows.values() if row["control"]]
    counts, offered = tally(corrections)
    control_counts, _ = tally(controls)
    print(
        f"  {label:22s} {len(rows):4d} rows   corrections {len(corrections):3d}:"
        f" {counts[COMMITTED]:3d} committed {counts[HELD]:3d} held"
        f" {counts[WRONG]:3d} WRONG  {offered:3d} offered   |"
        f"   controls {len(controls):3d}: {control_counts[INTACT]:3d} intact"
        f" {control_counts[WRONG]:3d} WRONG"
    )


def table(rows):
    """Per language and per class, over the rows every run agreed about."""
    order, grouped = [], {}
    for row in rows:
        key = (row["language"], row["class"])
        if key not in grouped:
            grouped[key] = []
            order.append(key)
        grouped[key].append(row)
    order.sort(key=lambda key: (key[0] != "he", key[1] == "must-not-correct", key[1]))

    language = None
    for key in order:
        if key[0] != language:
            language = key[0]
            print()
        group = grouped[key]
        counts, offered = tally(group)
        if key[1] == "must-not-correct":
            print(
                f"  {key[0]}  {key[1]:18s} {len(group):3d}"
                f"   {counts[INTACT]:3d} intact"
                f"   {counts[WRONG]:3d} WRONG"
            )
        else:
            print(
                f"  {key[0]}  {key[1]:18s} {len(group):3d}"
                f"   {counts[COMMITTED]:3d} committed"
                f"   {counts[HELD]:3d} held"
                f"   {counts[WRONG]:3d} WRONG"
                f"   {offered:3d} offered"
            )


def detail(row, prefix="    "):
    where = f" after {row['context']!r}" if row["context"] else ""
    print(
        f"{prefix}{row['id']:14s} {row['class']:18s} typed {row['typed']!r}"
        f" meant {row['intended']!r}{where}"
    )
    print(f"{prefix}  commits {row['commits']!r}   slots {row['slots']}")


def main():
    args = [argument for argument in sys.argv[1:] if not argument.startswith("--")]
    flags = {argument for argument in sys.argv[1:] if argument.startswith("--")}
    if len(args) < 2:
        print(__doc__.splitlines()[2].strip(), file=sys.stderr)
        return 2

    corpus = json.loads(pathlib.Path(args[0]).read_text())
    runs = [judge(corpus, json.loads(pathlib.Path(path).read_text())) for path in args[1:]]

    print(f"\n=== typo corpus: {len(runs)} run(s), {len(corpus['entries'])} pairs ===\n")
    for path, rows in zip(args[1:], runs):
        run_headline(rows, pathlib.Path(path).name)

    # A row has to answer the same way in every run before it is allowed into the
    # table. The verdict *and* the committed string, because two runs can land on
    # the same verdict by committing two different words and reporting that as
    # agreement would hide the instability this rule exists for.
    ids = [entry["id"] for entry in corpus["entries"]]
    stable, moved = [], []
    for rid in ids:
        seen = [rows[rid] for rows in runs if rid in rows]
        if len(seen) != len(runs):
            continue
        if len({row["verdict"] for row in seen}) > 1 or len({row["commits"] for row in seen}) > 1:
            moved.append((rid, seen))
        else:
            stable.append(seen[0])

    corrections = [row for row in stable if not row["control"]]
    controls = [row for row in stable if row["control"]]
    counts, offered = tally(corrections)
    control_counts, _ = tally(controls)
    rate = f"{100 * counts[COMMITTED] // len(corrections)}%" if corrections else "n/a"
    # One line, and it is the line to paste next to the same line from another
    # build. Everything in it is counted over the rows every run agreed about, so
    # two builds are compared on the same footing even when the unstable set moves.
    if len(runs) == 1:
        # Said out loud rather than left to be inferred from `stable 128/128`,
        # which on one run means "nothing was asked twice" and reads like
        # "everything agreed". `run.sh` passes two.
        print(
            "\n  ONE RUN: every row below counts by default, because there is nothing"
            "\n  to disagree with it. Hebrew answers move between runs; run it twice."
        )
    print(
        f"\nHEADLINE  typos {len(runs)} run(s) | stable {len(stable)}/{len(ids)} |"
        f" corrections {len(corrections)}: {counts[COMMITTED]} committed ({rate}),"
        f" {counts[HELD]} held, {counts[WRONG]} WRONG | offered {offered} |"
        f" controls {len(controls)}: {control_counts[INTACT]} intact,"
        f" {control_counts[WRONG]} WRONG"
    )

    print("\n  per language and class, over the rows every run agreed about:")
    table(stable)

    # **Never summarised away.** Worst first: a control row is a correctly spelled
    # word the keyboard rewrote, which is the failure people uninstall over, and a
    # correction row that landed on a third word is the same defect with an excuse.
    wrong = [row for row in stable if row["verdict"] == WRONG]
    wrong.sort(key=lambda row: (not row["control"], row["language"], row["class"]))
    print(f"\n  WRONG — the bold slot holds a word nobody typed or meant: {len(wrong)}")
    for row in wrong:
        detail(row)
        if row["control"]:
            print(f"      this word is spelled correctly: {row['note']}")

    missed = [row for row in corrections if row["verdict"] != COMMITTED and row["offered"]]
    print(f"\n  offered but not committed — the word was there and space refused it: {len(missed)}")
    for row in missed:
        print(
            f"    {row['id']:14s} typed {row['typed']!r} meant {row['intended']!r}"
            f"   commits {row['commits']!r}   the word is slot {row['offeredAt']}"
        )

    never = [row for row in corrections if not row["offered"]]
    print(f"\n  never ranked — intended word is absent from the engine array: {len(never)}")
    for row in never:
        print(f"    {row['id']:14s} typed {row['typed']!r} meant {row['intended']!r}   slots {row['slots']}")

    not_drawn = [
        row for row in corrections if row["offered"] and row["visibleOffered"] is False
    ]
    print(f"\n  ranked but not drawn — fourth candidate or echo filter: {len(not_drawn)}")
    for row in not_drawn:
        print(
            f"    {row['id']:14s} typed {row['typed']!r} meant {row['intended']!r}"
            f"   slots {row['slots']}  visible {row['visible']}"
        )

    ungenerated = [
        row for row in corrections if row["generatedOffered"] is False
    ]
    print(f"\n  never generated — no source produced the intended word: {len(ungenerated)}")
    for row in ungenerated:
        print(f"    {row['id']:14s} typed {row['typed']!r} meant {row['intended']!r}")

    # Same agreement discipline, and the same reason `SlotRecord.misspelled`
    # exists: the bold slot is not the only column a user can feel, and a bar
    # offering a string no list this keyboard consults has heard of is a defect
    # whatever space does about it.
    invented = []
    for rid in ids:
        seen = [rows[rid] for rows in runs if rid in rows]
        if len(seen) != len(runs) or any(row["misspelled"] is None for row in seen):
            continue
        shared = set(seen[0]["misspelled"])
        for row in seen[1:]:
            shared &= set(row["misspelled"])
        if shared:
            invented.append((seen[0], sorted(shared)))
    print(f"\n  non-words in an offered slot (every run): {len(invented)}")
    for row, words in invented:
        print(
            f"    {row['id']:14s} typed {row['typed']!r}"
            f" -> {', '.join(repr(word) for word in words)}   slots {row['slots']}"
        )

    print(f"\n  rows that moved between runs, counted nowhere above: {len(moved)}")
    for rid, seen in moved:
        answers = " | ".join(f"{row['verdict']}:{row['commits']!r}" for row in seen)
        print(f"    {rid:14s} typed {seen[0]['typed']!r}  {answers}")

    if "--verbose" in flags:
        print("\n  every stable row:")
        for row in stable:
            detail(row, prefix="    ")
    return 0


if __name__ == "__main__":
    sys.exit(main())
