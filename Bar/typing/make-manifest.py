#!/usr/bin/env python3
"""Folds the per-entry files the capture test wrote into reference/manifest.json.

Every corpus id gets a row. Ids the capture never reached are recorded as
uncaptured with a reason, so a reader can always tell the difference between
"the stock keyboard offered nothing" and "we never asked it".
"""

import json
import pathlib
import subprocess
from datetime import datetime, timezone

HERE = pathlib.Path(__file__).resolve().parent
REF = HERE / "reference"
RAW = REF / "raw"


def runtime_version() -> str:
    try:
        out = subprocess.run(
            ["xcrun", "simctl", "list", "devices", "booted"],
            capture_output=True, text=True, timeout=30).stdout
        for line in out.splitlines():
            if line.startswith("--"):
                return line.strip("- ").strip()
    except Exception:
        pass
    return "unknown"


def main() -> None:
    corpus = json.loads((HERE / "corpus.json").read_text())
    raw = {}
    if RAW.is_dir():
        for path in RAW.glob("*.json"):
            item = json.loads(path.read_text())
            raw[item["id"]] = item

    entries = []
    for entry in corpus["entries"]:
        eid = entry["id"]
        got = raw.get(eid)
        if got is None:
            entries.append({
                "id": eid,
                "status": "uncaptured",
                "reason": "the capture run never reached this entry",
            })
            continue
        row = {
            "id": eid,
            "status": got.get("status", "uncaptured"),
            "keyboardExpected": entry["keyboard"],
        }
        if got.get("status") == "captured":
            png = REF / got.get("screenshot", "")
            row["screenshot"] = got.get("screenshot") if png.is_file() else None
            row["keyboardActual"] = got.get("keyboardActual")
            row["fieldText"] = got.get("fieldText", "")
            row["suggestions"] = got.get("suggestions", [])
            if not row["suggestions"]:
                row["note"] = "the stock keyboard showed no suggestion bar for this input"
            if row["screenshot"] is None:
                row["status"] = "uncaptured"
                row["reason"] = "the screenshot file is missing"
        else:
            row["reason"] = got.get("reason", "unknown")
        entries.append(row)

    captured = sum(1 for e in entries if e["status"] == "captured")
    manifest = {
        "schema": 1,
        "capturedAt": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "device": "iPhone 17 Pro",
        "runtime": runtime_version(),
        "hostApp": "com.apple.reminders",
        "keyboard": "stock iOS, English (US) and Hebrew, no third-party keyboards installed",
        "corpus": "../corpus.json",
        "method": (
            "XCUITest drives Apple's Reminders app and taps out every character of "
            "context + prefix on the system keyboard, then screenshots the whole "
            "screen. Tapping is not an implementation detail: iOS keeps its own typing "
            "session, and text inserted any other way (paste, typeText) never joins "
            "it, so the bar ends up answering a different question."
        ),
        "suggestionsRead": (
            "Accessibility labels of the three slots under the element iOS labels "
            "'Typing Predictions', ordered left to right on screen. Hebrew renders "
            "right to left, so for Hebrew entries the last item in the list is the "
            "leftmost slot, not the least likely one."
        ),
        "fieldText": (
            "The text field's accessibility value at the moment of the screenshot. "
            "It includes iOS's grey inline completion, so on en-comp-01 it reads "
            "'I'll be there in ten minutes' even though only 'minu' was typed and "
            "the rest is an unaccepted suggestion. It also shows autocorrect's work "
            "on the context: 'Ill' was typed, 'I'll' is what stuck."
        ),
        "skippedCharacters": (
            "Characters the capture could not type, because reaching the numbers "
            "plane crashes the test runner on this simulator. In practice only the "
            "apostrophe, which iOS restores on the next space anyway."
        ),
        "totals": {
            "corpus": len(entries),
            "captured": captured,
            "uncaptured": len(entries) - captured,
        },
        "howToFillTheGaps": (
            "Run Bar/typing/capture.sh --resume. It keeps every entry already "
            "captured and re-attempts the rest, so coverage only goes up. Entries "
            "reading 'the capture run never reached this entry' are not evidence "
            "about the stock keyboard in either direction — nobody asked it."
        ),
        "entries": entries,
    }
    (REF / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    print(f"manifest.json: {captured} captured, {len(entries) - captured} uncaptured")


if __name__ == "__main__":
    main()
