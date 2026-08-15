# Drift: re-running the Bar corpora on a cadence

Every absolute number in `README.md` is a reading with a date on it. The model
behind `Bar/ai-text` and `Bar/screen-context` is served through a **moving
alias** and there is nothing to pin it to — every dated handle 404s on this
project and the API answers a successful call by echoing the alias back as its
own version. So quality can regress with no commit behind it, and until this
directory existed nothing would have noticed, because the harnesses only ran
when somebody remembered.

This is the unattended runner. One dated, append-only record per run, per
corpus, with the per-entry verdicts kept — because the rule this repo keeps
relearning is that the total moves for reasons the entries can explain and the
total cannot.

```bash
Bar/drift/harness/run.sh                    # the free set (grouped), then the trend check
Bar/drift/harness/run.sh --with-simulator   # adds Bar/typing, if a device is ALREADY booted
Bar/drift/harness/run.sh --paid             # adds Bar/ai-text and Bar/screen-context: REAL model calls
Bar/drift/harness/run.sh --only ai-text     # exactly this one, and --only SPENDS MONEY on a
                                            # paid corpus without --paid, deliberately
Bar/drift/harness/run.sh --trend-only       # reads the records, runs nothing
Bar/drift/harness/run.sh --no-trend         # writes the records, checks nothing
Bar/drift/harness/trend.py ai-text          # the same check on its own
Bar/drift/harness/trend.py --window 4       # 3 is the minimum the rule will accept
```

**Exit 0 clean, 4 the trend check fired, 3 a corpus was asked for and produced no
record.** A scheduled job wants to hear about both 4 and 3; see
[Installing it](#installing-it-which-is-yours-to-do), and read the money
paragraph there before you schedule the paid set.

The alert is 4, not 2, on purpose: `trend.py` and `run.py` both parse their
arguments with `argparse`, and `argparse` itself exits 2 on a usage error —
a missing `--window` value, an unknown corpus name. If the trend alert also
used 2, `trend.py --window` (forgot the value) and `trend.py grouped` (found a
real regression) would be indistinguishable by exit code alone, and a script
that branches on "2 means quality regressed" would open an issue for a typo.
2 stays argparse's; the alert moved to 4 instead.

## What runs, what it costs, and how often it is worth running

| Corpus | Cost of one run | Default | Cadence worth having |
|---|---|---|---|
| `grouped` | 30 to 70s of CPU. No simulator, no Swift, no network. | **on** | daily, or every push |
| `typing` | ~8s, but needs a booted iOS Simulator | off (`--with-simulator`) | weekly |
| `ai-text` | 58 generations plus 58 judge calls, and macOS 26 with Apple Intelligence on | off (`--paid`) | weekly at most |
| `screen-context` | 30 multimodal calls at half-size JPEG | off (`--paid`) | weekly at most |

**`grouped` is in the default set and it does not measure the shipping
keyboard.** It is the only corpus here that measures something this repo does not
ship — a keyboard whose keys each carry several letters — and it is pure Python
over frozen data, so it cannot drift. It earns its place for two other reasons:
it is free, and it proves every day that the runner itself still works. Read an
alert on it as "Python, the data files or the harness moved", never as a
regression in the keyboard.

**`typing` is off by default because it needs a simulator, and the runner
refuses rather than booting one.** `UITextChecker` is UIKit, and macOS would
spell-check with `NSSpellChecker` — a different dictionary and a different
ranking, so a macOS score is not a score of the shipping engine. The harness
runs through `xcrun simctl spawn`, which does **not** bring Simulator.app to the
front; what would is booting a device, so this runner never does. If nothing is
booted the corpus is skipped with the command that fixes it. A scheduled job
that steals the screen is worse than a corpus that went unmeasured.

**`dictation` and `layouts` are deliberately not wired in.** `Bar/dictation`
would be a third paid corpus (36 clips through Vertex, plus an Apple-model half
that needs the simulator), and `Bar/layouts` captures screenshots from a booted
device, which is the one thing this runner promises never to do. Adding
dictation is a small change — an adapter beside the other four in `run.py` — and
it should be a deliberate one, taken when somebody is prepared to pay for it
weekly.

## The trend rule, and the arithmetic behind it

**One run is not evidence.** Two runs of *identical* code disagree on ~17 of the
58 `ai-text` entries and swing the total by 1 to 5 points; `he-en` alone moved
14/17 to 10/17 with nothing changed. Judge and model are both sampled. An alarm
on a single delta would fire most weeks on nothing, be ignored inside a month,
and leave this repo worse off than it was with no alarm at all.

So the sampled corpora are judged across a **window**, W = 5 runs, against the
W runs before it. Two detectors, and the per-entry one is the sensitive half.

**Totals.** Median of the recent window against the median of the baseline
window. Medians, not means, so one broken night — a network outage answering
"no output" for half the corpus — cannot move the verdict on its own.

For two runs of a quantity with standard deviation `s`, the difference has
standard deviation `s*sqrt(2)` and mean absolute value `1.128*s`. A typical
observed difference near 3 points gives `s ~ 2.7`; treating the largest observed
difference of 5 as about two standard deviations of the difference gives
`s ~ 1.8`. Call it **s = 2.5 points on 58 entries**.

The median of W samples has standard error `1.253*s/sqrt(W)`, so the difference
of two medians has `1.253*s*sqrt(2/W)`. At W = 5 that is **2.0 points**, and a
2.5-sigma threshold is **5.0 points**. Only a *drop* is an alert, so the
false-alarm rate is the one-sided tail, **0.62% of checks**, not the 1.2%
two-sided figure this paragraph quoted first.

**Entries.** An entry that passed in *every* run of the baseline window and
failed in *every* run of the recent window. Per-entry flipping is the noise, so
a flip is worth nothing; an entry that flips and stays flipped is not. Take the
worst case, an entry that is a coin flip run to run (17 of 58 disagreeing
between two runs is what `p = 0.5` on those 17 looks like). The chance it passes
W times running and then fails W times running is `4^-W`, so with 17 such
entries the expected false flags per check is `17 * 4^-W`:

| W | expected false flags per check | at a weekly cadence |
|---|---|---|
| 3 | 0.27 | one every ~4 checks. Unshippable. |
| 4 | 0.066 | one every ~15 checks, so ~4 months |
| 5 | **0.017** | one every ~60 checks, so ~14 months |

W = 5 is the default for that reason, and `--window` moves it.

### What this instrument cannot see, stated plainly

- **Under 5 points on `ai-text` is invisible, by construction.** 5 points on 58
  entries is a 9% move in quality. A real 3-point regression will never fire the
  totals detector at this sample size, and no threshold choice fixes that: the
  noise floor is 1 to 5 points and the corpus is 58 entries. The per-entry
  detector is what catches the smaller, sharper kind of regression, where two or
  three entries break for good rather than everything sagging a little.
- **The per-entry detector needs 2W = 10 runs before it can fire at all.** At a
  weekly cadence that is ten weeks from the first run to the first possible
  alert. There is no way around it that does not also cry wolf; see the table.
- **Every floor above is derived from spread measured *within one sitting*, and
  this runner samples across days.** `Bar/screen-context/README.md` reports two
  runs minutes apart disagreeing on 2 of 30 frames, and a pair taken a day apart
  disagreeing on roughly a third of the corpus. So the across-day noise floor is
  larger than the numbers these thresholds are set from, and by an amount nobody
  has measured. That is why the threshold is
  `max(floor, 2.5 * standard error observed in the records)`: the floor stops a
  small sample producing an absurdly tight threshold, and the observed half lets
  a noisier reality raise it without anybody editing a file. **Re-derive the
  floors from the records once ~10 runs exist**; every report prints the spread
  it measured.
- The observed spread is pooled **within** each window, never across both. The
  first version took one standard deviation over all 2W values, which counts the
  step change as spread: fed a synthetic 7-point regression it raised its own
  threshold to 7.6 points and reported noise. A detector that hides what it is
  looking for is worse than none, and only a test with a known answer in it
  found that.

### Deterministic corpora are a different question

`grouped` is Python over frozen data and `typing` is a spell checker over a
frozen corpus. Neither samples a model: same inputs, same output. So a single
delta there **is** evidence — of a change in code, in data, or in the platform,
never of model drift — and those two are diffed run against previous run. **The
diff is every key of every entry plus every key of `metrics`, not the two fields
somebody remembered to compare.** The first version looked at `pass` and a
`value` that `typing` entries do not even carry, so seven entries could stop
committing the right word — `metrics.commit` 67 to 60, every `pass` unchanged —
and the report said "no unit moved". That is the `cs-11` class of defect, a
keyboard committing a word nobody asked for, reported as no change.

Two known wobbles are not defects: `typing`'s `he-comp-04` and `he-comp-05`
change slot 2 between runs because `UITextChecker` does, and that has never moved
a `commit` value. The record keys on `pass`, `commit` and the committed word
rather than on slot order, so neither can fire this.

## The records

One append-only JSON Lines file per corpus under `Bar/drift/runs/`. One line per
successful run, sorted by nothing but arrival, and read back sorted by `run`.

```jsonc
{
  "run": "2026-08-15T16:22:14Z",
  "corpus": "typing",
  "commit": "d47367e4",          // "tree": "clean" | "dirty" | "unknown" when git could not be asked
  "seconds": 7.7,
  "sampled": false,              // whether a single delta could ever mean anything
  "config": "simulator 0966F3D6-…",   // for screen-context, the model, scale and encoder
  "headline": { "name": "judged pass", "value": 73, "of": 76, "unit": "entries" },
  "metrics": { "commit": 67, "commit of": 70, "offered": 73, … },
  "entries": { "apos-09": { "pass": false, "commit": false, "commits": "were" }, … }
}
```

`entries` is the point of the file. `AGENTS.md` is explicit that per-entry
verdicts matter more than the total, and a record that kept only the total could
never answer *which* entries moved:

```bash
# which entries failed in the last ai-text run
python3 -c 'import json;r=[json.loads(l) for l in open("Bar/drift/runs/ai-text.jsonl")][-1];print([k for k,v in r["entries"].items() if v["pass"] is False])'
```

**A failed or half-failed run writes no record, and keeps what it paid for.** A
paid run where the judge errored on more than a tenth of the entries is an
infrastructure failure, not a reading, and one bad night inside the window would
drag a median that is there precisely to be robust. But 58 generations and 58
judge calls were still spent, and `preserved` was about to restore the corpus
directory over the top of them, so the artifacts are copied to
`Bar/drift/runs/failed/<timestamp>-<corpus>/` with a `why.txt` first. Score them
by hand or throw them away; do not let the runner delete them for you.

**The headline is scored out of what was actually answered.** `ai-text` reports
`good` out of the entries the judge returned a verdict for, not out of all 58,
because each unjudged entry otherwise costs exactly one point of headline — and
the tolerance above allows five of them, which is the same size as the whole
alert threshold. A flaky proxy for a month is persistent rather than noisy, so
medians are no defence: it would read as a five-point regression. `trend.py` puts
every window on the latest denominator and says so when they differed.

**A run that measures nothing exits 3 and says so at the bottom of the log**,
under `NOT MEASURED in this run`. It used to print `TREND: nothing fired` over a
report of stale records and exit 0, which is the exact silence this directory
exists to break: an expired gcloud token would have both paid corpora skipping
every Monday forever with a green light on top. `trend.py` separately alerts when
a corpus's newest record is older than its `max_age_days` (14 for `grouped`, 21
for the rest), because a `crontab -r`, a renamed path or a laptop that slept all
month look exactly like health otherwise.

**The corpus directories are left exactly as they were found.** Three harnesses
write over tracked files (`Bar/grouped/results.json`, `Bar/ai-text/real_outputs.json`
and its meta, `Bar/ai-text/scores.json`); the runner snapshots and restores them,
and `Bar/screen-context`'s output goes to a temporary name that is deleted. A
weekly job that leaves those dirty turns `git status` into noise and invites
somebody to commit a drift run as though it were a deliberate re-take — which is
exactly the trap `Bar/screen-context/README.md` names, because `cloud_outputs.json`
is replayed by `ScreenContextBarTests` and regenerating it moves every routed
threshold at the same moment as the thing being measured.

**Commit the `runs/*.jsonl` files.** They are the artifact; a trend that lives on
one machine is not a trend. They append, so the diff is the new lines.

## Installing it, which is yours to do

**Nothing here is scheduled, and that is deliberate.** Scheduling a job that
spends real money on model calls is the user's call, not the runner's, so the
paid corpora need `--paid` (or `--only <corpus>`, which names one explicitly and
counts as the same deliberate act) and no cron entry is installed by anything in
this repo.

The free set, weekly on Monday morning. Run this from the repo root:

```bash
(crontab -l 2>/dev/null; echo "5 9 * * 1 cd $PWD && Bar/drift/harness/run.sh >> ~/Library/Logs/bar-drift.log 2>&1 || tail -80 ~/Library/Logs/bar-drift.log | mail -s 'Bar drift needs reading' \$USER") | crontab -
```

`crontab -l` to read it back, `crontab -r` to remove it.

**The `|| mail` half is not decoration.** Redirecting both streams to a log is
what makes cron mail *nothing*, so an earlier version of this line had no
configuration in which a failure or an alert reached a human at all: the runner
exits 4 on an alert and 3 when it measured nothing, and both went into a file
nobody opens. Drop the redirection instead if you would rather cron mailed you
every run's full output. On stock macOS `mail` delivers to the local mailbox, so
either read it with `mail` or swap that command for whatever you actually check.

For the paid set, use launchd rather than cron: cron's PATH is short, `gcloud` is
usually not on it, and `Bar/ai-text/harness/run-real.sh` needs a token from it.
Save this whole file as `~/Library/LaunchAgents/com.nitai.bar-drift.plist` and
`launchctl load` it.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.nitai.bar-drift</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/zsh</string>
    <string>-lc</string>
    <string>cd ~/REPOS/ai-keyboard &amp;&amp; Bar/drift/harness/run.sh --paid</string>
  </array>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Weekday</key><integer>1</integer>
    <key>Hour</key><integer>9</integer>
    <key>Minute</key><integer>5</integer>
  </dict>
  <key>StandardOutPath</key><string>/Users/nitai/Library/Logs/bar-drift.log</string>
  <key>StandardErrorPath</key><string>/Users/nitai/Library/Logs/bar-drift.log</string>
</dict>
</plist>
```

**`Minute` is load-bearing and this snippet shipped without it.** launchd treats
an omitted `StartCalendarInterval` key as a wildcard, so `{Weekday, Hour}` alone
fires at 9:00, 9:01, 9:02 and on to 9:59: about 5 to 10 times the intended spend
in back-to-back paid reruns, every Monday. It also quietly breaks the detector,
because the windows are counted in *records* and not in time, so eight records
from one morning fill both windows and "ten weeks to the first alert" becomes two
halves of a single sitting — which is precisely the within-sitting spread
`AGENTS.md` says is not evidence.

Two more things to know before you schedule the paid line. It cannot run
`Bar/ai-text` unless macOS 26 is awake with Apple Intelligence enabled, because
the on-device half of `RoutedIntelligence` is measured on macOS and every
simulator runtime throws `ModelManagerError 1026` on its first call. And a weekly
cadence means the per-entry detector cannot say anything for ten weeks; running
the paid set more often buys sensitivity sooner and costs proportionally more.

## If you change this

- Do not touch the corpora. They are frozen on purpose; changing one invalidates
  every historical comparison, and the records here are only comparable because
  the exam did not move.
- A new corpus is one function in `run.py` plus a `Rule` in `trend.py`. Say
  whether it samples a model. Getting that wrong is the whole design: a sampled
  corpus judged as deterministic cries wolf every week, and a deterministic one
  judged as sampled sits on a real code regression for ten runs.
- Keep the per-entry verdicts small enough to append weekly forever. `ai-text`
  stores a verdict, the failed mechanical checks and the criteria that were
  unmet or violated, truncated to 90 characters, rather than the whole of
  `scores.json`.
