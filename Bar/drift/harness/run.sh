#!/bin/bash
# The drift runner: re-runs the Bar corpora on a cadence and writes one dated
# record per run, so quality moving underneath a frozen corpus shows up as a
# trend rather than as a surprise during a release.
#
#   Bar/drift/harness/run.sh                   # the free set (grouped), then the trend check
#   Bar/drift/harness/run.sh --with-simulator  # adds Bar/typing, only if a device is ALREADY booted
#   Bar/drift/harness/run.sh --paid            # adds Bar/ai-text and Bar/screen-context: REAL model calls
#   Bar/drift/harness/run.sh --only ai-text    # exactly this corpus, and --only SPENDS MONEY
#                                              # on a paid one without --paid, deliberately
#   Bar/drift/harness/run.sh --trend-only      # reads the records, runs nothing
#   Bar/drift/harness/run.sh --no-trend        # writes the records, checks nothing
#
# Exit 0 when the trend check found nothing, 2 when it fired, 3 when a corpus was
# asked for and produced no record. A scheduled job wants to hear about all of 2
# and 3: measuring nothing quietly is the failure this directory exists to catch.
#
# Two things this script will not do, and both are the point:
#
#   * it never boots a simulator and never opens Simulator.app. `Bar/typing`
#     needs a booted device, so it is off by default and refuses rather than
#     booting one — a background job stealing the screen is worse than a corpus
#     that went unmeasured.
#   * it never spends money on its own. The default set is free, and the paid
#     corpora need `--paid` — or `--only`, which names one corpus explicitly and
#     is treated as the same deliberate act. Scheduling either is the user's call.
#
# Everything about the cadence, the trend rule and the install command is in
# Bar/drift/README.md.
set -euo pipefail
cd "$(dirname "$0")"
exec python3 run.py "$@"
