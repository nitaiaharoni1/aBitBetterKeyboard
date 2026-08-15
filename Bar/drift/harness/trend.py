#!/usr/bin/env python3
"""The trend rule over `Bar/drift/runs/*.jsonl`, and the arithmetic behind it.

    Bar/drift/harness/trend.py                  # every corpus that has records
    Bar/drift/harness/trend.py ai-text
    Bar/drift/harness/trend.py --window 4       # 3 is the minimum; see below

Exit 0 when nothing fired, 4 when something did, so a scheduled job that only
mails on failure mails exactly when there is something to read. 4, not 2:
`argparse` itself exits 2 on a usage error, and a trend alert must not read as
a typo in the command line, or the reverse.

THE RULE, AND WHY IT IS NOT A SINGLE DELTA

Two runs of *identical* code disagree on ~17 of the 58 `ai-text` entries and
swing the total by 1 to 5 points; `he-en` alone moved 14/17 to 10/17 with nothing
changed. Judge and model are both sampled. So a single-delta alarm fires most
weeks on nothing at all, gets ignored inside a month, and leaves this repo worse
off than it was with no alarm — which is why the rule below only fires on
something that persists across a window of runs, and why `--window` refuses
anything below 3.

Three detectors. The per-entry one is the sensitive half, and the third is the
one that catches this whole directory quietly dying:

  totals    Median of the last W runs against the median of the W before it.
            Medians rather than means so that one broken night — a network
            outage answering "no output" for half the corpus — cannot move the
            verdict on its own.

  entries   An entry that passed in EVERY run of the baseline window and failed
            in EVERY run of the recent window. Per-entry flipping *is* the
            noise, so a flip is worthless; an entry that flips and then stays
            flipped is not.

  staleness A corpus whose last record is older than its cadence allows, or one
            that was asked for in this invocation and produced no record. A
            sleeping laptop, a `crontab -r`, a moved path or an expired gcloud
            token all otherwise read as "nothing fired" forever, which is
            exactly the "nothing would notice" failure this directory exists to
            prevent.

THE ARITHMETIC, ai-text, 58 entries

  Spread. Two runs differ by 1 to 5 points. For two runs X1, X2 of a quantity
  with standard deviation s, the difference has standard deviation s*sqrt(2) and
  a mean absolute value of 1.128*s. A typical observed |difference| near 3 gives
  s ~ 2.7; treating the largest observed difference of 5 as about two standard
  deviations of the difference gives s ~ 1.8. So s is about 2 to 2.7 points and
  the rule below is set from s = 2.5.

  Totals. The median of W samples has standard error 1.253*s/sqrt(W), so the
  difference of two medians has 1.253*s*sqrt(2/W). At W = 5 and s = 2.5 that is
  2.0 points, and a 2.5-sigma threshold is 5.0 points. Only a *drop* is an alert,
  so the false-alarm rate is the one-sided tail, 0.62% of checks, not the 1.2%
  two-sided figure an earlier version of this paragraph quoted. Below that
  threshold this instrument sees nothing: a 5-point move on 58 entries is a 9%
  change in quality, so a real 3-point regression is invisible to the totals
  detector and always will be at this sample size. That is the honest limit, and
  it is why the per-entry detector exists.

  Entries. Take the worst case, an entry that is a coin flip run to run (17 of 58
  disagreeing between two runs is what p = 0.5 on those 17 looks like). The
  chance it passes W times running and then fails W times running is 4^-W. With
  17 such entries the expected number of false flags per check is 17 * 4^-W:

      W = 3   0.27    one false flag every ~4 checks      too noisy to ship
      W = 4   0.066   one every ~15 checks                ~4 months at weekly
      W = 5   0.017   one every ~60 checks                ~14 months at weekly

  W = 5 is the default for that reason. The cost is stated plainly: the detector
  needs 2W = 10 runs before it can fire at all, which at a weekly cadence is ten
  weeks from the first run to the first possible alert. The report prints this
  rate from the number of entries that actually flipped in the window rather than
  from the 17 above, so it describes the corpus in front of it.

  The floors are estimates, and the records replace them. Every number above is
  derived from spread measured WITHIN one sitting, and this runner samples across
  days, where `Bar/screen-context/README.md` reports drift several times larger.
  So the threshold is `max(floor, 2.5 * standard error observed in the records)`
  — the floor stops a small sample producing an absurdly tight threshold, and the
  observed half lets a noisier reality raise it without anybody editing this
  file. The observed spread is printed on every report, so the floors here can be
  re-derived from real data once ~10 runs exist.

  That observed half is pooled WITHIN each window and never across both. The
  first version took one standard deviation over all 2W values, which counts the
  step change as spread: fed a synthetic 7-point regression it raised its own
  threshold to 7.6 points and reported noise. A detector that hides the thing it
  is looking for is worse than no detector, and only a test with a known answer
  in it would have found that.

  Denominators are made to agree before any of this runs. `ai-text` scores
  `good` out of the entries the judge actually answered, so a week when the judge
  errored on four calls has an `of` of 54 rather than 58. Comparing the raw
  counts would read those four as a four-point regression, which is the same
  class of mistake as the pooled variance: an infrastructure wobble wearing the
  costume of a quality change. Every headline is put on the latest run's
  denominator first, and the report says so when they differed.

DETERMINISTIC CORPORA ARE A DIFFERENT QUESTION

`grouped` is pure Python over frozen data and `typing` is a spell checker over a
frozen corpus; neither samples a model. Same inputs, same output. So a single
delta there IS evidence, and it is evidence of a change in code, in data, or in
the platform — not of model drift. Those two are diffed run against previous run
and any movement is reported: the headline, every key in `metrics`, and every
key of every entry. Comparing only `pass` was a real hole — seven `typing`
entries can stop committing the right word, moving `metrics.commit` from 67 to
60, with every `pass` unchanged, and the report said "no unit moved". That is the
`cs-11` class of defect, a keyboard committing a word nobody asked for, reported
as no change.

Two known wobbles are not defects: `typing`'s `he-comp-04` and `he-comp-05`
change slot 2 between runs because `UITextChecker` does, which has never moved a
`commit` value. The record keys on `pass`, `commit` and the committed word rather
than on slot order, so neither can fire this.
"""

from __future__ import annotations

import argparse
import json
import math
import statistics
import sys
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
RUNS = HERE.parent / "runs"

MINIMUM_WINDOW = 3


@dataclass(frozen=True)
class Rule:
    sampled: bool
    window: int = 5
    # Minimum headline movement, in the headline's own points, that may ever be
    # called a regression. See the arithmetic in the module docstring.
    floor: float = 5.0
    # Entries measured to flip between two runs of identical code. A fallback for
    # the false-flag arithmetic when the records themselves have not measured it.
    unstable: int = 17
    # How long a silence is allowed to look like health. Set to about twice the
    # cadence the README recommends, so one missed run is not an alert and a
    # month of missed runs is.
    max_age_days: int = 21


RULES = {
    "grouped": Rule(sampled=False, max_age_days=14),
    "typing": Rule(sampled=False),
    # 58 entries, s ~ 2.5 points.
    "ai-text": Rule(sampled=True, floor=5.0, unstable=17),
    # 30 frames. Within one sitting two runs disagreed on 2 of 30 and sender
    # moved by 1, so s ~ 1 there; across days an earlier pair disagreed on
    # roughly a third of the corpus, at a different configuration. The floor is
    # set from s = 1.5 as an inflation of the within-sitting figure and is the
    # least trustworthy number in this file until the records replace it.
    "screen-context": Rule(sampled=True, floor=3.0, unstable=10),
}

DEFAULT = Rule(sampled=True)


def load(corpus: str) -> list[dict]:
    """Every parseable record, loudest about the ones that are not.

    One torn line used to kill this outright, and permanently: `load` raised
    `JSONDecodeError` on it, so every future check exited 1 having read nothing,
    and the next appended record landed on the partial line and merged with it,
    eating a good reading as well. A record that cannot be read is one lost
    reading and must never be more than that.
    """
    path = RUNS / f"{corpus}.jsonl"
    if not path.exists():
        return []
    rows = []
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not line.strip():
            continue
        try:
            row = json.loads(line)
            row["headline"]["value"], row["headline"]["of"]  # noqa: B018 - shape check
        except Exception as broken:  # noqa: BLE001
            print(f"  !! {path.name}:{number} is unreadable and was dropped ({broken}). "
                  f"One lost reading, not a broken series.")
            continue
        rows.append(row)
    return sorted(rows, key=lambda row: row["run"])


def known() -> list[str]:
    return sorted(path.stem for path in RUNS.glob("*.jsonl")) if RUNS.exists() else []


def headline(row: dict) -> float:
    return float(row["headline"]["value"])


def on_one_denominator(rows: list[dict]) -> tuple[list[float], int, bool]:
    """Headlines rescaled to the latest run's `of`.

    `ai-text` scores out of the entries the judge answered, so a flaky judge
    shrinks the denominator and the raw count falls for a reason that has nothing
    to do with quality.
    """
    reference = int(rows[-1]["headline"]["of"]) or 1
    varied = len({int(row["headline"]["of"]) for row in rows}) > 1
    values = [
        headline(row) * reference / (int(row["headline"]["of"]) or reference) for row in rows
    ]
    return values, reference, varied


def verdicts(rows: list[dict]) -> dict[str, list]:
    """entry id -> its `pass` in each of these runs, missing runs included as None."""
    ids = sorted({key for row in rows for key in row["entries"]})
    return {key: [row["entries"].get(key, {}).get("pass") for row in rows] for key in ids}


def age_of(row: dict) -> timedelta:
    stamp = datetime.strptime(row["run"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    return datetime.now(timezone.utc) - stamp


def _differs(old, new) -> bool:
    if isinstance(old, (int, float)) and isinstance(new, (int, float)):
        return abs(float(old) - float(new)) > 1e-6
    return old != new


def _changes(old: dict, new: dict) -> list[str]:
    """Every key that moved, not only the two somebody remembered to compare."""
    out = []
    for key in sorted(set(old) | set(new)):
        if _differs(old.get(key), new.get(key)):
            out.append(f"{key} {old.get(key)!r} -> {new.get(key)!r}")
    return out


def check_deterministic(corpus: str, rows: list[dict]) -> list[str]:
    alerts = []
    if len(rows) < 2:
        print("  only one record; nothing to compare it to yet")
        return alerts
    before, after = rows[-2], rows[-1]
    delta = headline(after) - headline(before)
    print(f"  deterministic: {before['run'][:10]} ({before['commit']}) "
          f"-> {after['run'][:10]} ({after['commit']})")
    print(f"  {after['headline']['name']}: {headline(before)} -> {headline(after)}  "
          f"delta {delta:+.3f}")

    metrics = _changes(before.get("metrics", {}), after.get("metrics", {}))
    moved = []
    for key in sorted(set(before["entries"]) | set(after["entries"])):
        changes = _changes(before["entries"].get(key, {}), after["entries"].get(key, {}))
        if changes:
            moved.append((key, changes))

    if not moved and not metrics and abs(delta) < 1e-9:
        print("  no metric and no unit moved. Same inputs, same answers, which is what this "
              "corpus is for.")
        return alerts

    alerts.append(
        f"{corpus}: {len(metrics)} metric(s) and {len(moved)} unit(s) moved in a harness that "
        "does not sample. That is a change in code, data or the platform, not model drift."
    )
    for line in metrics:
        print(f"  !! metrics.{line}")
    for key, changes in moved[:20]:
        print(f"  !! {key}: {'; '.join(changes)}")
    if len(moved) > 20:
        print(f"     ... and {len(moved) - 20} more")
    return alerts


def _variance(values: list[float]) -> float:
    return statistics.variance(values) if len(values) > 1 else 0.0


def check_sampled(corpus: str, rows: list[dict], rule: Rule, window: int) -> list[str]:
    alerts = []
    need = 2 * window
    print("  sampled: both the model and the judge. A single delta is not evidence here.")
    if len(rows) < need:
        print(f"  {len(rows)} of the {need} records the rule needs (window {window} x 2). "
              f"Nothing can fire yet.")
        _print_series(rows)
        return alerts

    span = rows[-need:]
    scaled, reference, varied = on_one_denominator(span)
    baseline, recent = rows[-need:-window], rows[-window:]
    early, late = scaled[:window], scaled[window:]
    before, after = statistics.median(early), statistics.median(late)
    delta = after - before
    # Pooled WITHIN each window, never across both, and that is not a detail.
    # A single standard deviation over all 2W values counts the step change
    # itself as spread, so a real 7-point drop pushed the threshold to 7.6 and
    # hid itself — found by feeding the rule a synthetic regression it was
    # supposed to catch. Within-window pooling is blind to the shift between
    # windows, which is the whole quantity being tested.
    spread = math.sqrt((_variance(early) + _variance(late)) / 2)
    standard_error = 1.253 * spread * math.sqrt(2 / window)
    threshold = max(rule.floor, round(2.5 * standard_error, 1))

    print(f"  {recent[-1]['headline']['name']}, of {reference}")
    if varied:
        print(f"  note: the denominator moved across these {need} runs "
              f"({', '.join(str(r['headline']['of']) for r in span)}); every value above is "
              f"rescaled to {reference}, or a flaky judge would read as a regression.")
    print(f"  baseline {baseline[0]['run'][:10]}..{baseline[-1]['run'][:10]}  median {before:g}")
    print(f"  recent   {recent[0]['run'][:10]}..{recent[-1]['run'][:10]}  median {after:g}")
    print(f"  spread   SD {spread:.2f} pooled within the two windows of {window} "
          f"-> SE(median difference) {standard_error:.2f} "
          f"-> threshold max(floor {rule.floor}, 2.5 SE {2.5 * standard_error:.1f}) = {threshold}")
    print(f"  delta    {delta:+.1f}")

    if delta <= -threshold:
        alerts.append(
            f"{corpus}: the headline dropped {abs(delta):.1f} points across two windows of "
            f"{window}, past the {threshold}-point threshold."
        )
    elif delta >= threshold:
        print("  the headline ROSE past the threshold. Not an alert, but not nothing either: "
              "an unexplained improvement is drift too.")
    else:
        print(f"  inside the threshold, so it is noise as far as this instrument can tell. "
              f"Anything under {threshold} points is invisible here by construction.")

    columns = verdicts(span)
    flipped = [key for key, series in columns.items() if len({v for v in series if v is not None}) > 1]
    print(f"  entries  {len(flipped)} of {len(columns)} flipped at least once across these "
          f"{need} runs. That is the noise floor, measured here rather than remembered.")
    # Quoted from what actually flipped here, not from the configured 17, so the
    # rate describes the corpus in front of the reader. Zero flips means the
    # per-entry detector cannot raise a false flag at all, which is worth saying
    # rather than dividing by.
    unstable = len(flipped)
    expected = unstable * (4.0 ** -window)
    if expected > 0:
        print(f"  a persistent flip needs {window} clean passes then {window} clean failures; "
              f"at {unstable} unstable entries that is {expected:.3f} expected false flags per "
              f"check (1 in {1 / expected:.0f}).")
    else:
        print(f"  a persistent flip needs {window} clean passes then {window} clean failures; "
              f"nothing flipped in this window, so nothing here can flag falsely.")

    regressed, recovered = [], []
    for key, series in columns.items():
        older, newer = series[:window], series[window:]
        if all(v is True for v in older) and all(v is False for v in newer):
            regressed.append(key)
        if all(v is False for v in older) and all(v is True for v in newer):
            recovered.append(key)

    if regressed:
        alerts.append(
            f"{corpus}: {len(regressed)} entr{'y' if len(regressed) == 1 else 'ies'} "
            f"passed {window}/{window} then failed {window}/{window}: {', '.join(sorted(regressed))}"
        )
        for key in sorted(regressed):
            print(f"  !! {key} {_why(recent[-1]['entries'].get(key, {}))}")
    if recovered:
        print(f"  recovered (failed {window}/{window} then passed {window}/{window}): "
              f"{', '.join(sorted(recovered))}")
    if not regressed and not recovered:
        print("  no entry crossed and stayed crossed.")
    return alerts


def _why(entry: dict) -> str:
    bits = []
    if entry.get("verdict"):
        bits.append(f"verdict {entry['verdict']}")
    if entry.get("failedChecks"):
        bits.append("failed " + ",".join(entry["failedChecks"]))
    if entry.get("violated"):
        bits.append("violated " + "; ".join(entry["violated"]))
    if entry.get("unmet"):
        bits.append("unmet " + "; ".join(entry["unmet"]))
    if entry.get("message") is not None:
        bits.append(f"message {entry['message']}")
        bits.append("sender ok" if entry.get("sender") else "sender WRONG")
    return "  ".join(bits) or "no detail recorded"


def _print_series(rows: list[dict]) -> None:
    for row in rows:
        print(f"    {row['run'][:16]}  {headline(row):>7g} of {row['headline']['of']}  "
              f"{row['commit']} {row['tree']}")


def check_freshness(corpus: str, rows: list[dict], rule: Rule, unmeasured: bool) -> list[str]:
    """A silent runner and a healthy one look identical without this."""
    alerts = []
    if unmeasured:
        alerts.append(
            f"{corpus}: asked for in this run and produced no record, so nothing below is "
            "a reading of today."
        )
    if not rows:
        return alerts
    age = age_of(rows[-1])
    days = age.total_seconds() / 86400
    if days > rule.max_age_days:
        alerts.append(
            f"{corpus}: the last record is {days:.0f} days old, past the {rule.max_age_days} "
            "this corpus allows. Nothing is measuring it: check the schedule, not the keyboard."
        )
    else:
        print(f"  last record {days:.1f} days old (stale past {rule.max_age_days})")
    return alerts


def report(only: list[str] | None = None, window: int | None = None,
           unmeasured: list[str] | None = None) -> int:
    unmeasured = list(unmeasured or [])
    names = list(only or known())
    for name in unmeasured:
        if name not in names:
            names.append(name)
    if not names:
        print(f"no records under {RUNS}; run Bar/drift/harness/run.sh first")
        return 0

    alerts: list[str] = []
    for corpus in names:
        rows = load(corpus)
        rule = RULES.get(corpus, DEFAULT)
        span = window or rule.window
        print(f"\n=== {corpus} ===")
        if not rows:
            print("  no records yet")
            alerts += check_freshness(corpus, rows, rule, corpus in unmeasured)
            continue
        print(f"  {len(rows)} record(s), {rows[0]['run'][:10]} .. {rows[-1]['run'][:10]}"
              + (f"   last run {rows[-1]['seconds']}s" if rows[-1].get("seconds") else ""))
        alerts += check_freshness(corpus, rows, rule, corpus in unmeasured)
        if any(row["tree"] != "clean" for row in rows[-2 * span:]):
            print("  note: at least one recent record was taken over an uncommitted or "
                  "unreadable tree, so it is a reading of nobody's commit.")
        if rule.sampled:
            alerts += check_sampled(corpus, rows, rule, span)
        else:
            alerts += check_deterministic(corpus, rows)

    print()
    if not alerts:
        print("TREND: nothing fired.")
        return 0
    print("TREND: something needs reading.")
    for line in alerts:
        print(f"  !! {line}")
    return 4


def main() -> None:
    parser = argparse.ArgumentParser(
        description="The trend rule over Bar/drift/runs/*.jsonl.",
        epilog="Exit 0 when nothing fired, 4 when something did. (argparse itself exits 2 on "
               "a usage error, so the trend alert does not share that code.)",
    )
    parser.add_argument("corpus", nargs="*", help="which corpora to check (default: all with records)")
    parser.add_argument("--window", type=int, default=None,
                        help=f"runs per window (default 5, minimum {MINIMUM_WINDOW})")
    args = parser.parse_args()

    if args.window is not None and args.window < MINIMUM_WINDOW:
        # A window of 1 is precisely the single-delta alarm the whole design
        # exists to avoid, and 2 is not far off it: see the false-flag table.
        parser.error(
            f"--window below {MINIMUM_WINDOW} is the single-delta alarm this rule exists to "
            "avoid; at W=1 every run of identical code fires on the ~17 of 58 entries that "
            "flip by themselves"
        )
    unknown = [name for name in args.corpus if name not in RULES and not (RUNS / f"{name}.jsonl").exists()]
    if unknown:
        parser.error(f"no records and no rule for: {', '.join(unknown)}")
    raise SystemExit(report(args.corpus or None, window=args.window))


if __name__ == "__main__":
    main()
