#!/usr/bin/env python3
"""Re-runs the Bar corpora unattended and writes one dated record per run.

    Bar/drift/harness/run.sh                   # the free set (grouped), then the trend check
    Bar/drift/harness/run.sh --with-simulator  # adds Bar/typing, only if a device is ALREADY booted
    Bar/drift/harness/run.sh --paid            # adds Bar/ai-text and Bar/screen-context: real calls
    Bar/drift/harness/run.sh --only typing --only grouped
    Bar/drift/harness/run.sh --only ai-text    # SPENDS MONEY: --only bypasses the --paid gate
    Bar/drift/harness/run.sh --trend-only      # reads the records, runs nothing
    Bar/drift/harness/run.sh --no-trend        # writes the records, checks nothing

Exit 0 when the trend check found nothing, 4 when it fired, 3 when a corpus was
asked for and produced no record. 4, not 2: `argparse` exits 2 on a usage
error, and a trend alert must never collide with a typo in the command line.

Why this exists: every absolute number in `README.md` is a reading with a date
on it. The model is served behind a moving alias with no dated version to pin to
— every dated handle 404s and the API answers by echoing the alias back as its
own version — so quality can regress with no commit behind it, and today nothing
would notice, because the harnesses only run when somebody remembers.

What it does NOT do is alarm on a single delta. Two runs of identical code
disagree on ~17 of the 58 `ai-text` entries and swing the total by 1 to 5 points.
An alarm on one delta would fire most weeks, be ignored inside a month, and leave
this worse off than no alarm at all. `trend.py` holds the rule and the arithmetic
behind it; `Bar/drift/README.md` states plainly what the noise floor makes
invisible.

Three properties are load-bearing and easy to break by "tidying":

  * The corpus directories are left exactly as found. Three harnesses write over
    a *tracked* file, and a weekly job that leaves those dirty invites somebody
    to commit a drift run as a deliberate re-take — which moves the committed
    reference at the same moment as the thing being measured.
  * Nothing here boots a simulator, and nothing opens Simulator.app.
  * A half-failed paid run is not a data point. It is dropped rather than
    appended, because one broken run inside the window drags the median — but
    its artifacts are copied to `runs/failed/` first, because they were paid for.
  * A run that measured nothing exits 3 and says so at the bottom of the log. A
    scheduled job that quietly stops measuring is the exact failure this
    directory exists to prevent.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path

# The scorers are imported rather than re-implemented, and importing a module
# writes a `__pycache__` beside it. A frozen corpus directory growing an
# untracked directory every Monday is exactly the git noise this runner exists
# not to make.
sys.dont_write_bytecode = True

HERE = Path(__file__).resolve().parent
DRIFT = HERE.parent
BAR = DRIFT.parent
REPO = BAR.parent
RUNS = DRIFT / "runs"


class Skip(Exception):
    """This corpus cannot run here, and that is not a failure of the runner."""


# ---------------------------------------------------------------------------
# Plumbing


@contextmanager
def preserved(*paths: Path):
    """Puts every file back exactly as it was found, including "was not there".

    `Bar/grouped/harness/run.py` writes `results.json` with no way to redirect
    it, and the ai-text harness writes `real_outputs.json`, its meta file and
    `scores.json` the same way. All four are tracked. The dated copy of every
    run lives in `Bar/drift/runs/`, so the corpus directory does not need to
    carry the last unattended run — and must not, or `git status` fills with
    diffs nobody made and `Bar/screen-context/README.md`'s warning about
    re-taking a reference by accident becomes very easy to walk into.
    """
    saved = [(path, path.read_bytes() if path.exists() else None) for path in paths]
    try:
        yield
    finally:
        for path, blob in saved:
            if blob is None:
                path.unlink(missing_ok=True)
            else:
                path.write_bytes(blob)


def shell(command: list[str], env: dict[str, str] | None = None) -> str:
    """Runs a harness and fails loudly with its own output rather than a traceback."""
    merged = dict(os.environ)
    # The Python harnesses import their own modules, and every import drops a
    # `__pycache__` into a frozen corpus directory. `sys.dont_write_bytecode`
    # covers this process only; a subprocess needs telling separately.
    merged["PYTHONDONTWRITEBYTECODE"] = "1"
    merged.update(env or {})
    print(f"  $ {' '.join(str(c) for c in command)}", file=sys.stderr)
    finished = subprocess.run(
        [str(c) for c in command],
        cwd=str(REPO),
        env=merged,
        capture_output=True,
        text=True,
    )
    if finished.returncode != 0:
        tail = (finished.stdout + finished.stderr).strip().splitlines()[-25:]
        raise RuntimeError(
            f"{command[0]} exited {finished.returncode}\n    " + "\n    ".join(tail)
        )
    return finished.stdout


def module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    loaded = importlib.util.module_from_spec(spec)
    # Registered before it is executed: `@dataclass` resolves its annotations
    # through `sys.modules[cls.__module__]`, so a module executed without being
    # registered there dies on its first dataclass — which `trend.py` has.
    sys.modules[name] = loaded
    spec.loader.exec_module(loaded)
    return loaded


def git(*args: str) -> str | None:
    """The output, or `None` when git could not be asked.

    `None` and `""` are different answers and this file is about honesty: an
    empty `git status --porcelain` means the tree is clean, while a git that did
    not run means nobody knows. Collapsing them recorded an unreadable tree as
    `clean`.
    """
    try:
        return subprocess.run(
            ["git", *args], cwd=str(REPO), capture_output=True, text=True, check=True
        ).stdout.strip()
    except Exception:  # noqa: BLE001 - a record without a commit is still a record
        return None


def booted_simulator() -> str:
    """The udid of a device somebody already booted, or "".

    Deliberately does not boot one. A scheduled job is allowed to measure this
    machine; it is not allowed to change what is running on it, and `simctl
    boot` is one `open -a Simulator` away from a window landing on top of
    whatever the user is doing.
    """
    if override := os.environ.get("SIMULATOR_DEVICE"):
        return override
    try:
        listing = json.loads(
            subprocess.run(
                ["xcrun", "simctl", "list", "devices", "booted", "-j"],
                capture_output=True,
                text=True,
                check=True,
            ).stdout
        )
    except Exception:  # noqa: BLE001
        return ""
    for runtime in listing.get("devices", {}).values():
        for device in runtime:
            return device["udid"]
    return ""


def vertex_token() -> str:
    """The same token `Bar/ai-text/harness/run-real.sh` uses, obtained the same way."""
    if token := os.environ.get("VERTEX_ACCESS_TOKEN"):
        return token
    token = subprocess.run(
        ["gcloud", "auth", "print-access-token", "--account=nitai@handi.co.il"],
        capture_output=True,
        text=True,
    ).stdout.strip()
    if not token:
        raise Skip("no Vertex token: set VERTEX_ACCESS_TOKEN or run `gcloud auth login`")
    return token


def record(corpus: str, seconds: float, sampled: bool, headline: dict,
           metrics: dict, entries: dict, config: str = "") -> dict:
    head = git("rev-parse", "--short", "HEAD")
    status = git("status", "--porcelain")
    return {
        "run": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "corpus": corpus,
        "commit": head or "unknown",
        # A record taken over uncommitted edits is still worth keeping — it is
        # usually the most interesting one — but it is not a reading of any
        # commit, and the trend report says so rather than quietly averaging it
        # in with the others. `unknown` is a third answer, not a synonym for
        # clean.
        "tree": "unknown" if status is None else ("dirty" if status else "clean"),
        "seconds": round(seconds, 1),
        "sampled": sampled,
        "config": config,
        "headline": headline,
        "metrics": metrics,
        "entries": entries,
    }


def append(row: dict) -> Path:
    """One line, one `write(2)`, on a descriptor opened O_APPEND.

    A buffered text write is not one syscall. An `ai-text` row is tens of
    kilobytes against an 8 KiB buffer, so it leaves the process as several
    writes, and two overlapping runs under O_APPEND interleave into a line
    neither can parse. That torn line then poisons the series: the reader used to
    die on it, and the next append landed on the partial line and merged with it,
    eating a good reading too. `load()` now survives a torn line; this stops one
    being written in the first place.
    """
    RUNS.mkdir(parents=True, exist_ok=True)
    path = RUNS / f"{row['corpus']}.jsonl"
    blob = json.dumps(row, ensure_ascii=False, sort_keys=True).encode("utf-8") + b"\n"
    # A file that does not end in a newline is one somebody or something
    # truncated. Start a fresh line rather than gluing onto theirs.
    if path.exists() and (size := path.stat().st_size):
        with path.open("rb") as handle:
            handle.seek(size - 1)
            if handle.read(1) != b"\n":
                blob = b"\n" + blob
    descriptor = os.open(path, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o644)
    try:
        written = 0
        while written < len(blob):
            written += os.write(descriptor, blob[written:])
    finally:
        os.close(descriptor)
    return path


def rescue(corpus: str, why: str, *paths: Path) -> Path | None:
    """Keeps the artifacts of a paid run that is about to produce no record.

    `preserved` puts the corpus directory back on the way out, which is right for
    a run that worked and ruinous for one that did not: 58 generations plus 58
    judge calls were spent, six came back unjudged, the record was refused, and
    the finally block then deleted everything that had been paid for. The copy
    lands in `Bar/drift/runs/failed/` where it can be scored by hand.
    """
    existing = [path for path in paths if path.exists()]
    if not existing:
        return None
    kept = RUNS / "failed" / f"{datetime.now(timezone.utc):%Y%m%dT%H%M%SZ}-{corpus}"
    kept.mkdir(parents=True, exist_ok=True)
    for path in existing:
        shutil.copy2(path, kept / path.name)
    (kept / "why.txt").write_text(why + "\n", encoding="utf-8")
    return kept


# ---------------------------------------------------------------------------
# The corpora. One function each, returning a record.


def run_grouped() -> dict:
    """Free: no simulator, no Swift, no network. Seconds, not minutes.

    It is also the only one of the four that measures something this repo does
    not ship, so read an alert here as "the runner's own inputs moved" — Python,
    the data files, or the harness — and never as a regression in the keyboard.
    It is in the default set because a canary that costs nothing is worth having
    and because it proves weekly that the runner itself still works.
    """
    data = BAR / "grouped" / "data"
    missing = [
        name
        for name in ("rows.json", "testtext.json", "lexicon-en.json", "lexicon-he.json")
        if not (data / name).exists()
    ]
    if missing:
        # `lexicon-*.json` is gitignored, so a fresh checkout is *expected* to be
        # missing it. Same message `Bar/grouped/harness/run.py` gives.
        raise Skip(
            "missing " + ", ".join(missing) + " in Bar/grouped/data/; "
            "regenerate them, see Bar/grouped/README.md"
        )

    results = BAR / "grouped" / "results.json"
    started = time.time()
    with preserved(results):
        shell([BAR / "grouped" / "harness" / "run.sh"])
        payload = json.loads(results.read_text(encoding="utf-8"))

    entries, metrics = {}, {}
    for row in payload["results"]:
        key = f"{row['language']}/{row['condition']}/k{row['k']}"
        entries[key] = {
            "pass": None,
            "value": round(100 * row["withContext"]["commitRate"], 3),
            "offered": round(100 * row["withContext"]["offeredRate"], 3),
        }
        if row["condition"] == "adjacent" and row["dial"]:
            metrics[f"{row['language']} {row['dial']} commit"] = entries[key]["value"]

    headline = {
        "name": "he adjacent L2 commit",
        "value": metrics.get("he L2 commit", 0.0),
        "of": 100,
        "unit": "percent",
    }
    return record(
        "grouped", time.time() - started, sampled=False,
        headline=headline, metrics=metrics, entries=entries,
        config=str(payload.get("rows", "")),
    )


def run_typing() -> dict:
    """Needs an iOS Simulator, because `UITextChecker` is UIKit.

    Not in the default set, and it refuses rather than booting a device: see
    `booted_simulator`. `run.sh` takes an output path, so nothing tracked is
    written — `Bar/typing/engine_outputs.json` is left alone entirely.
    """
    device = booted_simulator()
    if not device:
        raise Skip(
            "no simulator is booted, and this runner never boots one. "
            "Boot a device yourself (`xcrun simctl boot 'iPhone 17 Pro'`) and re-run."
        )

    started = time.time()
    workspace = Path(tempfile.mkdtemp(prefix="bar-drift-typing-"))
    try:
        outputs = workspace / "engine_outputs.json"
        shell(
            [BAR / "typing" / "harness" / "run.sh", outputs],
            env={"SIMULATOR_DEVICE": device},
        )
        scorer = module(BAR / "typing" / "harness" / "score.py", "bar_typing_score")
        rows = scorer.score(scorer.load(outputs), scorer.load(scorer.corpus_path()))
    finally:
        shutil.rmtree(workspace, ignore_errors=True)

    entries = {
        row["id"]: {
            "pass": row["pass"],
            "commit": row["commit"],
            "offered": row["offered"],
            "commits": row["commits"],
        }
        for row in rows
    }
    judged = [row for row in rows if row["pass"] is not None]
    committed = [row for row in rows if row["commit"] is not None]
    metrics = {
        "judged pass": sum(1 for row in judged if row["pass"]),
        "judged of": len(judged),
        "commit": sum(1 for row in committed if row["commit"]),
        "commit of": len(committed),
        "offered": sum(1 for row in rows if row["offered"]),
    }
    headline = {
        "name": "judged pass",
        "value": metrics["judged pass"],
        "of": len(judged),
        "unit": "entries",
    }
    return record(
        "typing", time.time() - started, sampled=False,
        headline=headline, metrics=metrics, entries=entries,
        config=f"simulator {device}",
    )


def run_ai_text() -> dict:
    """Paid, twice over: 58 generations, then 58 judge calls.

    Needs macOS 26 with Apple Intelligence on for the on-device half and a
    gcloud token for the Vertex half, exactly as `run-real.sh` says. Both the
    engine and the judge are sampled, which is where the ~17-of-58 flip and the
    1-to-5-point swing come from, so this is the corpus the trend rule was
    written for.
    """
    harness = BAR / "ai-text" / "harness"
    outputs = BAR / "ai-text" / "real_outputs.json"
    meta = BAR / "ai-text" / "real_outputs.meta.json"
    scores = BAR / "ai-text" / "scores.json"
    token = vertex_token()

    started = time.time()
    with preserved(outputs, meta, scores):
        # Everything that can fail happens inside `preserved`, so the rescue can
        # run before the restore takes the artifacts away.
        try:
            shell([harness / "run-real.sh"], env={"VERTEX_ACCESS_TOKEN": token})
            shell(
                [sys.executable, harness / "score.py", "--judge"],
                env={"VERTEX_ACCESS_TOKEN": token},
            )
            payload = json.loads(scores.read_text(encoding="utf-8"))

            entries = {}
            for entry_id, row in sorted(payload.items()):
                failed = sorted(k for k, (ok, _) in row["mechanical"].items() if not ok)
                judged = row.get("judged")
                judged = judged if isinstance(judged, dict) and "verdict" in judged else {}
                verdict = judged.get("verdict")
                entries[entry_id] = {
                    # A judge call that errored is `None`, not a failure. The
                    # persistence rule needs an unbroken run of passes then an
                    # unbroken run of failures, so an unjudged entry breaks the
                    # streak and cannot raise a false alarm out of somebody's
                    # flaky network.
                    "pass": None if verdict is None else (verdict == "good" and not failed),
                    "verdict": verdict,
                    "failedChecks": failed,
                    "unmet": [
                        c["criterion"][:90]
                        for c in judged.get("must_results", [])
                        if not c.get("met")
                    ],
                    "violated": [
                        c["criterion"][:90]
                        for c in judged.get("must_not_results", [])
                        if c.get("violated")
                    ],
                }

            unjudged = [i for i, e in entries.items() if e["pass"] is None]
            if len(unjudged) > len(entries) // 10:
                raise Skip(
                    f"{len(unjudged)} of {len(entries)} entries came back unjudged; "
                    "that is an infrastructure failure, not a reading, so no record was written"
                )
        except Exception as failure:  # noqa: BLE001 - re-raised below
            kept = rescue("ai-text", str(failure), outputs, meta, scores)
            if kept:
                print(f"    kept what this run paid for in {kept}", file=sys.stderr)
            raise

    good = sum(1 for e in entries.values() if e["verdict"] == "good")
    metrics = {
        "good": good,
        "partial": sum(1 for e in entries.values() if e["verdict"] == "partial"),
        "bad": sum(1 for e in entries.values() if e["verdict"] == "bad"),
        "unjudged": len(unjudged),
        "mechanicalClean": sum(1 for e in entries.values() if not e["failedChecks"]),
        "mustNotViolations": sum(len(e["violated"]) for e in entries.values()),
    }
    # Out of what the judge actually answered, never out of all 58. Each entry
    # the judge errored on used to cost exactly one point of headline, and the
    # tolerance above allows five of them — the same size as the alert
    # threshold, so a month of a flaky proxy reads as a five-point regression
    # that medians cannot defend against, because it is persistent rather than
    # noisy. `trend.py` puts every window on one denominator to match.
    headline = {
        "name": "good verdicts",
        "value": good,
        "of": len(entries) - len(unjudged),
        "unit": "entries",
    }
    return record(
        "ai-text", time.time() - started, sampled=True,
        headline=headline, metrics=metrics, entries=entries,
        config="run-real.sh + score.py --judge",
    )


def run_screen_context() -> dict:
    """Paid: 30 multimodal calls.

    Sent at the size and encoding the capture process actually uploads — half
    size, JPEG — because `vertex_vision.py` defaults to the full PNG every older
    score used, and a drift series has to measure what ships. The config string
    goes into every record, so a series taken at two configurations can be told
    apart later instead of read as a regression.
    """
    harness = BAR / "screen-context" / "harness"
    # Named for this runner, and deleted afterwards: `cloud_outputs.json` and
    # `cloud_outputs_repeat.json` are replayed by `ScreenContextBarTests`, so
    # overwriting either would move every routed threshold at the same moment as
    # the thing being measured.
    outputs = BAR / "screen-context" / "drift_outputs.json"
    token = vertex_token()

    started = time.time()
    with preserved(outputs):
        try:
            shell(
                [sys.executable, harness / "vertex_vision.py", outputs.name],
                env={
                    "VERTEX_ACCESS_TOKEN": token,
                    "VERTEX_IMAGE_SCALE": "2",
                    "VERTEX_IMAGE_FORMAT": "jpeg",
                },
            )
            rows = json.loads(outputs.read_text(encoding="utf-8"))
        except Exception as failure:  # noqa: BLE001 - re-raised below
            # 30 multimodal calls were paid for. `preserved` is about to delete
            # the only copy of what came back.
            kept = rescue("screen-context", str(failure), outputs)
            if kept:
                print(f"    kept what this run paid for in {kept}", file=sys.stderr)
            raise

    scorer = module(harness / "score_cloud.py", "bar_screen_context_score")
    truth = json.loads((BAR / "screen-context" / "ground-truth.json").read_text())
    by_id = {entry["id"]: entry for entry in truth["images"]}

    entries = {}
    for row in rows:
        entry = by_id[row["id"]]
        expected = entry.get("expected")
        message = scorer.normalise(row.get("message"))
        sender = scorer.normalise(row.get("sender"))

        if expected is None:
            # The deliberate nothing-to-reply-to screen: silence is the answer.
            quiet = not message
            entries[row["id"]] = {
                "pass": quiet, "message": 1.0 if quiet else 0.0,
                "sender": quiet, "language": quiet, "trap": False, "ghost": False,
            }
            continue

        similarity = scorer.similarity(expected.get("message"), message)
        trap = any(
            scorer.normalise(t["text"]) and scorer.normalise(t["text"]) == message
            for t in entry.get("traps", [])
        )
        ghost = any(
            len(scorer.normalise(g if isinstance(g, str) else g.get("text", ""))) >= 8
            and scorer.normalise(g if isinstance(g, str) else g.get("text", "")) in message
            for g in entry.get("notOnScreen", [])
        )
        entries[row["id"]] = {
            "pass": similarity == 1.0 and scorer.similarity(expected.get("sender"), sender) == 1.0,
            "message": round(similarity, 4),
            "sender": scorer.similarity(expected.get("sender"), sender) == 1.0,
            "language": row.get("detectedLanguage") == expected.get("language"),
            "trap": trap,
            "ghost": ghost,
        }

    exact = sum(1 for e in entries.values() if e["message"] == 1.0)
    metrics = {
        "exactMessage": exact,
        "nearMessage": sum(1 for e in entries.values() if 0.9 <= e["message"] < 1.0),
        "sender": sum(1 for e in entries.values() if e["sender"]),
        "language": sum(1 for e in entries.values() if e["language"]),
        "traps": sum(1 for e in entries.values() if e["trap"]),
        "ghosts": sum(1 for e in entries.values() if e["ghost"]),
    }
    headline = {
        "name": "exact message", "value": exact, "of": len(entries), "unit": "frames",
    }
    return record(
        "screen-context", time.time() - started, sampled=True,
        headline=headline, metrics=metrics, entries=entries,
        config=(rows[0].get("config") if rows else ""),
    )


CORPORA = {
    # name: (function, paid, needs a simulator)
    "grouped": (run_grouped, False, False),
    "typing": (run_typing, False, True),
    "ai-text": (run_ai_text, True, False),
    "screen-context": (run_screen_context, True, False),
}


# ---------------------------------------------------------------------------


def selection(args) -> list[str]:
    if args.only:
        unknown = [name for name in args.only if name not in CORPORA]
        if unknown:
            sys.exit(f"unknown corpus: {', '.join(unknown)}; pick from {', '.join(CORPORA)}")
        return list(args.only)
    chosen = []
    for name, (_, paid, simulator) in CORPORA.items():
        if paid and not args.paid:
            continue
        if simulator and not args.with_simulator:
            continue
        chosen.append(name)
    return chosen


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Re-runs the Bar corpora and appends one dated record per run.",
        epilog="Exit 0 clean, 4 the trend check fired, 3 a corpus was asked for and "
               "produced no record. (2 is argparse's own usage-error code, left alone.)",
    )
    parser.add_argument("--paid", action="store_true",
                        help="also run the corpora that spend real model calls")
    parser.add_argument("--with-simulator", action="store_true",
                        help="also run Bar/typing, if a device is already booted")
    parser.add_argument("--only", action="append", default=[], metavar="CORPUS",
                        help="run exactly this corpus, INCLUDING a paid one without --paid "
                             "(repeatable)")
    parser.add_argument("--window", type=int, default=None,
                        help="runs per window in the trend check (default 5, minimum 3)")
    parser.add_argument("--trend-only", action="store_true",
                        help="read the records and check the trend; run nothing")
    parser.add_argument("--no-trend", action="store_true",
                        help="write the records and stop, without the trend check")
    args = parser.parse_args()
    if args.window is not None and args.window < 3:
        parser.error("--window below 3 is the single-delta alarm this design exists to avoid")

    selected = [] if args.trend_only else selection(args)
    written, missed = [], []
    for name in selected:
        runner, _, _ = CORPORA[name]
        print(f"==> {name}", file=sys.stderr)
        try:
            row = runner()
        except Skip as reason:
            print(f"    skipped: {reason}", file=sys.stderr)
            missed.append((name, f"skipped: {str(reason).splitlines()[0]}"))
            continue
        except Exception as failure:  # noqa: BLE001
            # A failed harness writes no record on purpose. A run that half
            # happened is not a reading, and the median is the whole defence
            # against one bad night. Caught broadly so a harness that changed
            # its output shape costs one corpus rather than the whole
            # invocation, trend check included.
            print(f"    FAILED: {failure}", file=sys.stderr)
            missed.append((name, f"failed: {str(failure).splitlines()[0]}"))
            continue
        path = append(row)
        head = row["headline"]
        print(
            f"    {head['name']}: {head['value']} of {head['of']}"
            f"   ({row['seconds']}s, {row['commit']}, {row['tree']})  -> {path.name}",
            file=sys.stderr,
        )
        written.append(name)

    code = 0
    if not args.no_trend:
        trend = module(HERE / "trend.py", "bar_drift_trend")
        code = trend.report(
            selected or None, window=args.window, unmeasured=[name for name, _ in missed]
        )

    # Said again at the bottom, where a scheduled job's log is actually read. A
    # run that measured nothing used to print "TREND: nothing fired" and exit 0,
    # which is the silence this whole directory exists to break: an expired
    # gcloud token would have both paid corpora skipping quietly every Monday
    # forever, over a trend report of records from March.
    if missed:
        print()
        print("NOT MEASURED in this run, so nothing above is a reading of today:")
        for name, why in missed:
            print(f"  !! {name}: {why}")
        code = 3
    raise SystemExit(code)


if __name__ == "__main__":
    main()
