"""The Python half of the fidelity check: asks the questions, diffs the answers.

    python3 python_side.py queries  > queries.json
    python3 python_side.py compare queries.json swift.json

Compared structurally rather than as text. The two JSON writers disagree about
key order and about how a Double is spelled, and a `diff` over that would report
formatting as a defect — which is how a real disagreement gets ignored.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

import rank  # noqa: E402

CORPUS = HERE.parent.parent / "corpus.json"

# The three queries `.claude/docs/test-suite-state.md` names as the ones a
# ranker change has to be judged on, plus the emoji that argument is about.
# These are dumped rung by rung so a disagreement is readable.
EXPLAIN = [
    {"query": "car", "emoji": ["🚗", "🚕", "🚙", "🥕", "🗂️"], "recent": []},
    {"query": "heart", "emoji": ["❤️", "🫀", "💏", "💗"], "recent": []},
    {"query": "לב", "emoji": ["❤️", "🫀", "💏", "💗"], "recent": []},
    # Niqqud, which is where a code-point length count goes wrong.
    {"query": "מורה", "emoji": ["👩‍🏫"], "recent": []},
    {"query": "רופא", "emoji": ["🩺"], "recent": []},
]

# Coverage is a Double crossing a JSON boundary twice. The result lists are
# compared exactly; this tolerance applies only to the diagnostic dump.
COVERAGE_TOLERANCE = 1e-12


def questions() -> dict:
    corpus = json.loads(CORPUS.read_text(encoding="utf-8"))
    queries = [
        {
            "id": entry["id"],
            "query": entry["query"],
            "recent": entry.get("recent", []),
            "limit": 60,
        }
        for entry in corpus["entries"]
    ]
    # Every single letter of both alphabets as well, because a corpus is 98
    # hand-picked queries and a port can be right on all of them and wrong on
    # the first keystroke of a word nobody wrote down. These are the widest
    # result sets the engine ever produces.
    for letter in "abcdefghijklmnopqrstuvwxyz":
        queries.append({"id": f"sweep-{letter}", "query": letter, "recent": [], "limit": 60})
    for letter in "אבגדהוזחטיכלמנסעפצקרשת":
        queries.append({"id": f"sweep-{letter}", "query": letter, "recent": [], "limit": 60})
    return {"queries": queries, "explain": EXPLAIN}


def compare(questions_path: Path, swift_path: Path) -> int:
    asked = json.loads(questions_path.read_text(encoding="utf-8"))
    swift = json.loads(swift_path.read_text(encoding="utf-8"))
    problems: list[str] = []

    catalogue = rank.catalog()
    if swift["catalogue"]["count"] != len(catalogue.all):
        problems.append(
            f"catalogue size: swift {swift['catalogue']['count']}, "
            f"python {len(catalogue.all)}"
        )
    if swift["catalogue"]["first"] != catalogue.all[0]:
        problems.append("catalogue order: first emoji differs")
    if swift["catalogue"]["last"] != catalogue.all[-1]:
        problems.append("catalogue order: last emoji differs")

    agreed = 0
    for question in asked["queries"]:
        mine = rank.results(question["query"], question["recent"], question["limit"])
        theirs = swift["results"].get(question["id"], [])
        if mine == theirs:
            agreed += 1
            continue
        first = next(
            (
                i
                for i in range(max(len(mine), len(theirs)))
                if mine[i : i + 1] != theirs[i : i + 1]
            ),
            0,
        )
        problems.append(
            f"{question['id']} ({question['query']!r}) diverges at rank {first + 1}: "
            f"swift {''.join(theirs[first:first + 4])!r} vs "
            f"python {''.join(mine[first:first + 4])!r}"
        )

    for item in asked["explain"]:
        for emoji in item["emoji"]:
            key = f"{item['query']}|{emoji}"
            theirs = swift["explain"].get(key)
            if theirs is None:
                problems.append(f"{key}: swift returned no match record")
                continue
            mine = rank.explain(item["query"], emoji)
            if theirs["names"] != mine["names"]:
                problems.append(f"{key}: names differ")
            for field in ("rung", "length"):
                value = mine[field]
                if value is None:
                    value = rank.INT_MAX
                if theirs[field] != value:
                    problems.append(
                        f"{key}: {field} swift {theirs[field]} vs python {value}"
                    )
            coverage = mine["coverage"] if mine["coverage"] is not None else 0.0
            if abs(theirs["coverage"] - coverage) > COVERAGE_TOLERANCE:
                problems.append(
                    f"{key}: coverage swift {theirs['coverage']} vs python {coverage}"
                )

    # Printed every run, agreement or not. A check whose only output is the
    # word "ok" is a check nobody can tell from a check that ran on nothing —
    # these are the three queries `test-suite-state.md` argues about, and
    # seeing both sides answer them wrongly *in the same way* is the evidence.
    print("")
    for eid in ("en-car", "en-heart", "he-lev"):
        question = next((q for q in asked["queries"] if q["id"] == eid), None)
        if question is None:
            continue
        theirs = swift["results"].get(eid, [])[:8]
        mine = rank.results(question["query"], question["recent"], 8)
        flag = "same" if mine == theirs else "DIFFER"
        print(f"  {question['query']:<8} swift {''.join(theirs)}")
        print(f"  {'':<8} python {''.join(mine)}   [{flag}]")
    print("")

    print(f"{agreed}/{len(asked['queries'])} result lists identical")
    print(f"{sum(len(i['emoji']) for i in asked['explain'])} match records compared")
    if problems:
        print("")
        for problem in problems:
            print(f"  FAIL {problem}")
        print("")
        print("The Python port and the shipping Swift disagree. Every number in")
        print("Bar/emoji/results.json is a number about the port, so it is a number")
        print("about nothing until this is green again.")
        return 1
    print("the port and the shipping engine agree exactly")
    return 0


if __name__ == "__main__":
    if sys.argv[1:2] == ["queries"]:
        json.dump(questions(), sys.stdout, ensure_ascii=False)
        sys.exit(0)
    if sys.argv[1:2] == ["compare"] and len(sys.argv) == 4:
        sys.exit(compare(Path(sys.argv[2]), Path(sys.argv[3])))
    print(__doc__)
    sys.exit(2)
